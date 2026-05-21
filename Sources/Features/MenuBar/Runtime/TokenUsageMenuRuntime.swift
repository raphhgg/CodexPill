import Foundation

@MainActor
final class TokenUsageMenuRuntime {
    private let provider: TokenUsageMenuProviding
    private let onStateChange: (TokenUsageMenuLoadState) -> Void
    private var refreshTask: Task<Void, Never>?
    private var refreshPeriod: CodexTokenUsagePeriod?
    private var loadedPeriod: CodexTokenUsagePeriod?
    private var lastProgressRenderDate: Date?

    private(set) var loadState: TokenUsageMenuLoadState = .loading(nil)

    init(
        provider: TokenUsageMenuProviding,
        onStateChange: @escaping (TokenUsageMenuLoadState) -> Void
    ) {
        self.provider = provider
        self.onStateChange = onStateChange
    }

    func handleEnabledChange(isEnabled: Bool, period: CodexTokenUsagePeriod) {
        guard isEnabled else {
            cancel()
            return
        }

        if !loadState.hasCachedData {
            loadState = .loading(nil)
        }
        refreshIfNeeded(period: period)
    }

    func handlePeriodChange(period: CodexTokenUsagePeriod) {
        guard loadedPeriod != period else { return }
        if !loadState.hasCachedData {
            loadState = .loading(nil)
        }
        refreshIfNeeded(period: period)
    }

    func refreshIfNeeded(period: CodexTokenUsagePeriod) {
        if refreshPeriod == period, refreshTask != nil {
            return
        }
        if loadedPeriod == period, loadState.hasCachedData {
            return
        }

        refreshTask?.cancel()
        refreshTask = nil
        refreshPeriod = period
        loadedPeriod = nil

        let provider = provider
        refreshTask = Task.detached { [weak self, provider] in
            // Keep the filesystem scan independent from the transient menu view.
            let loadState = await provider.load(period: period) { progress in
                Task { @MainActor [weak self] in
                    self?.updateProgress(progress, period: period)
                }
            }
            guard !Task.isCancelled else { return }
            await self?.finishRefresh(loadState, period: period)
        }
    }

    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshPeriod = nil
        loadedPeriod = nil
        lastProgressRenderDate = nil
    }

    private func updateProgress(_ progress: TokenUsageScanProgress, period: CodexTokenUsagePeriod) {
        guard refreshPeriod == period else { return }

        loadState = .loading(progress)
        let now = Date()
        let shouldRender = progress.scannedFiles == 0 ||
            progress.scannedFiles == progress.totalFiles ||
            progress.scannedFiles.isMultiple(of: 10) ||
            lastProgressRenderDate.map { now.timeIntervalSince($0) >= 0.35 } ?? true

        guard shouldRender else { return }
        lastProgressRenderDate = now
        onStateChange(loadState)
    }

    private func finishRefresh(_ loadState: TokenUsageMenuLoadState, period: CodexTokenUsagePeriod) {
        guard refreshPeriod == period else { return }
        self.loadState = loadState
        lastProgressRenderDate = nil
        refreshTask = nil
        refreshPeriod = nil
        if loadState.hasCachedData {
            loadedPeriod = period
        }
        onStateChange(loadState)
    }
}

enum TokenUsageMenuLoadState: Equatable {
    case loading(TokenUsageScanProgress?)
    case loaded([CodexDailyTokenUsage])
    case unavailable

    var hasCachedData: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}

protocol TokenUsageMenuProviding {
    func load(
        period: CodexTokenUsagePeriod,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState
}

struct LocalCodexSessionTokenUsageMenuProvider: TokenUsageMenuProviding {
    private let cache: LocalCodexSessionTokenUsageCache

    init(
        scanner: CodexSessionTokenUsageScanner = CodexSessionTokenUsageScanner(),
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true),
        cacheFile: URL = LocalCodexSessionTokenUsageDiskCache.defaultCacheFile(),
        now: @escaping () -> Date = Date.init
    ) {
        cache = LocalCodexSessionTokenUsageCache(
            scanner: scanner,
            sessionsDirectory: sessionsDirectory,
            diskCache: LocalCodexSessionTokenUsageDiskCache(cacheFile: cacheFile),
            now: now
        )
    }

    func load(
        period: CodexTokenUsagePeriod,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void = { _ in }
    ) async -> TokenUsageMenuLoadState {
        await cache.load(period: period, progress: progress)
    }
}

private actor LocalCodexSessionTokenUsageCache {
    private let scanner: CodexSessionTokenUsageScanner
    private let sessionsDirectory: URL
    private let diskCache: LocalCodexSessionTokenUsageDiskCaching
    private let now: () -> Date
    private var cachedEntriesByPeriod: [CodexTokenUsagePeriod: TokenUsageCacheEntry] = [:]

    init(
        scanner: CodexSessionTokenUsageScanner,
        sessionsDirectory: URL,
        diskCache: LocalCodexSessionTokenUsageDiskCaching,
        now: @escaping () -> Date
    ) {
        self.scanner = scanner
        self.sessionsDirectory = sessionsDirectory
        self.diskCache = diskCache
        self.now = now
    }

    func load(
        period: CodexTokenUsagePeriod,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        if let entry = cachedEntry(covering: period) {
            return .loaded(buckets(from: entry, for: period))
        }

        if let entry = diskCache.readEntry(covering: period) {
            cachedEntriesByPeriod[entry.period] = entry
            return .loaded(buckets(from: entry, for: period))
        }

        return await refresh(period: period, progress: progress)
    }

    private func refresh(
        period: CodexTokenUsagePeriod,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        do {
            let result = try scanner.scan(
                sessionsDirectory: sessionsDirectory,
                period: period,
                now: now(),
                progress: progress
            )
            let entry = TokenUsageCacheEntry(
                period: period,
                generatedAt: Date(),
                buckets: result.buckets
            )
            cachedEntriesByPeriod[period] = entry
            diskCache.writeEntry(entry)
            return .loaded(result.buckets)
        } catch is CancellationError {
            return .loading(nil)
        } catch {
            return .unavailable
        }
    }

    private func cachedEntry(
        covering period: CodexTokenUsagePeriod
    ) -> TokenUsageCacheEntry? {
        cachedEntriesByPeriod.values
            .filter { $0.period.dayCount >= period.dayCount }
            .sorted { $0.period.dayCount < $1.period.dayCount }
            .first
    }

    private func buckets(from entry: TokenUsageCacheEntry, for period: CodexTokenUsagePeriod) -> [CodexDailyTokenUsage] {
        Array(entry.buckets.suffix(period.dayCount))
    }

}

private protocol LocalCodexSessionTokenUsageDiskCaching {
    func readEntry(covering period: CodexTokenUsagePeriod) -> TokenUsageCacheEntry?
    func writeEntry(_ entry: TokenUsageCacheEntry)
}

private struct TokenUsageCacheEntry: Codable, Equatable {
    var period: CodexTokenUsagePeriod
    var generatedAt: Date
    var buckets: [CodexDailyTokenUsage]
}

private struct LocalCodexSessionTokenUsageDiskCache: LocalCodexSessionTokenUsageDiskCaching {
    private static let schemaVersion = 1

    let cacheFile: URL
    private let fileManager: FileManager

    init(cacheFile: URL, fileManager: FileManager = .default) {
        self.cacheFile = cacheFile
        self.fileManager = fileManager
    }

    static func defaultCacheFile(fileManager: FileManager = .default) -> URL {
        let cachesRoot = (try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return cachesRoot
            .appendingPathComponent("CodexPill", isDirectory: true)
            .appendingPathComponent("token-usage-cache.json")
    }

    func readEntry(covering period: CodexTokenUsagePeriod) -> TokenUsageCacheEntry? {
        readPayload()?.entries.values
            .filter { $0.period.dayCount >= period.dayCount }
            .sorted { $0.period.dayCount < $1.period.dayCount }
            .first
    }

    func writeEntry(_ entry: TokenUsageCacheEntry) {
        do {
            try fileManager.createDirectory(
                at: cacheFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var payload = readPayload() ?? CachePayload(schemaVersion: Self.schemaVersion, entries: [:])
            payload.entries[String(entry.period.rawValue)] = entry
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: cacheFile, options: [.atomic])
        } catch {
            // Token usage cache is derived data; failed writes should not affect the menu.
        }
    }

    private func readPayload() -> CachePayload? {
        guard let data = try? Data(contentsOf: cacheFile),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data),
              payload.schemaVersion == Self.schemaVersion
        else {
            return nil
        }
        return payload
    }

    private struct CachePayload: Codable {
        var schemaVersion: Int
        var entries: [String: TokenUsageCacheEntry]
    }
}
