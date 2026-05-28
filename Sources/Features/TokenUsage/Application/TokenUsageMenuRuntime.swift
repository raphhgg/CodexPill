import Foundation

private let tokenUsageMenuDefaultFreshnessInterval: TimeInterval = 15 * 60

@MainActor
final class TokenUsageMenuRuntime {
    private let provider: TokenUsageMenuProviding
    private let freshnessInterval: TimeInterval
    private let calendar: Calendar
    private let now: () -> Date
    private let onStateChange: (TokenUsageMenuLoadState) -> Void
    private var refreshTask: Task<Void, Never>?
    private var refreshRequest: TokenUsageMenuLoadRequest?
    private var loadedRequest: TokenUsageMenuLoadRequest?
    private var loadedAt: Date?
    private var lastProgressRenderDate: Date?

    private(set) var loadState: TokenUsageMenuLoadState = .loading(nil)

    init(
        provider: TokenUsageMenuProviding,
        freshnessInterval: TimeInterval = tokenUsageMenuDefaultFreshnessInterval,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        onStateChange: @escaping (TokenUsageMenuLoadState) -> Void
    ) {
        self.provider = provider
        self.freshnessInterval = freshnessInterval
        self.calendar = calendar
        self.now = now
        self.onStateChange = onStateChange
    }

    func handleEnabledChange(isEnabled: Bool, period: CodexTokenUsagePeriod, peakScope: TokenUsagePeakScope) {
        guard isEnabled else {
            cancel()
            return
        }

        if !loadState.hasCachedData {
            loadState = .loading(nil)
        }
        refreshIfNeeded(period: period, peakScope: peakScope)
    }

    func handlePeriodChange(period: CodexTokenUsagePeriod, peakScope: TokenUsagePeakScope) {
        let request = TokenUsageMenuLoadRequest(period: period, peakScope: peakScope)
        guard loadedRequest != request else { return }
        if !loadState.hasCachedData {
            loadState = .loading(nil)
        }
        refreshIfNeeded(period: period, peakScope: peakScope)
    }

    func refreshIfNeeded(period: CodexTokenUsagePeriod, peakScope: TokenUsagePeakScope) {
        let request = TokenUsageMenuLoadRequest(period: period, peakScope: peakScope)
        if refreshRequest == request, refreshTask != nil {
            return
        }
        let forceRefresh = loadedRequest == request && loadState.hasCachedData
        if forceRefresh, isLoadedDataFresh(at: now()) {
            return
        }

        refreshTask?.cancel()
        refreshTask = nil
        refreshRequest = request
        loadedRequest = nil
        loadedAt = nil

        let provider = provider
        refreshTask = Task.detached { [weak self, provider, request] in
            // Keep the filesystem scan independent from the transient menu view.
            let loadState = await provider.load(
                period: request.period,
                peakScope: request.peakScope,
                forceRefresh: forceRefresh
            ) { progress in
                Task { @MainActor [weak runtime = self] in
                    runtime?.updateProgress(progress, request: request)
                }
            }
            guard !Task.isCancelled else { return }
            await self?.finishRefresh(loadState, request: request)
        }
    }

    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshRequest = nil
        loadedRequest = nil
        loadedAt = nil
        lastProgressRenderDate = nil
    }

    private func updateProgress(_ progress: TokenUsageScanProgress, request: TokenUsageMenuLoadRequest) {
        guard refreshRequest == request else { return }

        if request.peakScope == .allTime,
           case .loaded(var data) = loadState,
           data.allTimePeak == nil {
            data.allTimePeakProgress = progress
            loadState = .loaded(data)
        } else {
            loadState = .loading(progress)
        }
        let now = Date()
        let shouldRender = progress.scannedFiles == 0 ||
            progress.scannedFiles == progress.totalFiles ||
            progress.scannedFiles.isMultiple(of: 10) ||
            lastProgressRenderDate.map { now.timeIntervalSince($0) >= 0.35 } ?? true

        guard shouldRender else { return }
        lastProgressRenderDate = now
        onStateChange(loadState)
    }

    private func finishRefresh(_ loadState: TokenUsageMenuLoadState, request: TokenUsageMenuLoadRequest) {
        guard refreshRequest == request else { return }
        self.loadState = loadState
        lastProgressRenderDate = nil
        refreshTask = nil
        refreshRequest = nil
        if loadState.hasCachedData {
            loadedRequest = request
            loadedAt = now()
        }
        onStateChange(loadState)
    }

    private func isLoadedDataFresh(at referenceDate: Date) -> Bool {
        guard let loadedAt else { return false }
        guard calendar.startOfDay(for: loadedAt) == calendar.startOfDay(for: referenceDate) else {
            return false
        }
        return referenceDate.timeIntervalSince(loadedAt) < freshnessInterval
    }
}

enum TokenUsageMenuLoadState: Equatable {
    case loading(TokenUsageScanProgress?)
    case loaded(TokenUsageMenuLoadedData)
    case unavailable

    var hasCachedData: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}

struct TokenUsageMenuLoadedData: Equatable {
    var buckets: [CodexDailyTokenUsage]
    var allTimePeak: CodexDailyTokenUsage?
    var allTimePeakProgress: TokenUsageScanProgress? = nil
}

private struct TokenUsageMenuLoadRequest: Equatable {
    var period: CodexTokenUsagePeriod
    var peakScope: TokenUsagePeakScope
}

protocol TokenUsageMenuProviding {
    func load(
        period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        forceRefresh: Bool,
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
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        cache = LocalCodexSessionTokenUsageCache(
            scanner: scanner,
            sessionsDirectory: sessionsDirectory,
            diskCache: LocalCodexSessionTokenUsageDiskCache(cacheFile: cacheFile),
            now: now,
            calendar: calendar
        )
    }

    func load(
        period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope = .currentPeriod,
        forceRefresh: Bool = false,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void = { _ in }
    ) async -> TokenUsageMenuLoadState {
        await cache.load(period: period, peakScope: peakScope, forceRefresh: forceRefresh, progress: progress)
    }
}

private actor LocalCodexSessionTokenUsageCache {
    private let scanner: CodexSessionTokenUsageScanner
    private let sessionsDirectory: URL
    private let diskCache: LocalCodexSessionTokenUsageDiskCaching
    private let now: () -> Date
    private let calendar: Calendar
    private var cachedEntriesByPeriod: [CodexTokenUsagePeriod: TokenUsageCacheEntry] = [:]

    init(
        scanner: CodexSessionTokenUsageScanner,
        sessionsDirectory: URL,
        diskCache: LocalCodexSessionTokenUsageDiskCaching,
        now: @escaping () -> Date,
        calendar: Calendar
    ) {
        self.scanner = scanner
        self.sessionsDirectory = sessionsDirectory
        self.diskCache = diskCache
        self.now = now
        self.calendar = calendar
    }

    func load(
        period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        forceRefresh: Bool,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        let referenceDate = now()
        if !forceRefresh, let entry = cachedEntry(covering: period, peakScope: peakScope, now: referenceDate) {
            return .loaded(loadedData(from: entry, for: period))
        }

        if !forceRefresh, let entry = diskCache.readEntry(
            covering: period,
            peakScope: peakScope,
            isUsable: { $0.coversCurrentWindow(for: period, now: referenceDate, calendar: calendar) }
        ) {
            cachedEntriesByPeriod[entry.period] = entry
            return .loaded(loadedData(from: entry, for: period))
        }

        return await refresh(period: period, peakScope: peakScope, progress: progress)
    }

    private func refresh(
        period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) async -> TokenUsageMenuLoadState {
        do {
            let result = try scanner.scan(
                sessionsDirectory: sessionsDirectory,
                period: period,
                now: now(),
                progress: progress
            )
            let cachedPeak = cachedEntriesByPeriod.values
                .filter(\.hasAllTimePeak)
                .compactMap(\.allTimePeak)
                .max { $0.usage.totalTokens < $1.usage.totalTokens }
            let refreshedAllTimePeak = peakScope == .allTime
                ? try scanner.scanAllHistory(sessionsDirectory: sessionsDirectory, progress: progress)
                    .buckets.max { $0.usage.totalTokens < $1.usage.totalTokens }
                : nil
            let allTimePeak = [cachedPeak, refreshedAllTimePeak]
                .compactMap { $0 }
                .max { $0.usage.totalTokens < $1.usage.totalTokens }
            let entry = TokenUsageCacheEntry(
                period: period,
                generatedAt: Date(),
                buckets: result.buckets,
                allTimePeak: allTimePeak,
                allTimePeakCoversAllHistory: allTimePeak != nil
            )
            cachedEntriesByPeriod[period] = entry
            diskCache.writeEntry(entry)
            return .loaded(loadedData(from: entry, for: period))
        } catch is CancellationError {
            return .loading(nil)
        } catch {
            return .unavailable
        }
    }

    private func cachedEntry(
        covering period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        now: Date
    ) -> TokenUsageCacheEntry? {
        cachedEntriesByPeriod.values
            .filter { $0.period.dayCount >= period.dayCount }
            .filter { peakScope == .currentPeriod || $0.hasAllTimePeak }
            .filter { $0.coversCurrentWindow(for: period, now: now, calendar: calendar) }
            .sorted { $0.period.dayCount < $1.period.dayCount }
            .first
    }

    private func loadedData(from entry: TokenUsageCacheEntry, for period: CodexTokenUsagePeriod) -> TokenUsageMenuLoadedData {
        TokenUsageMenuLoadedData(
            buckets: Array(entry.buckets.suffix(period.dayCount)),
            allTimePeak: entry.allTimePeak,
            allTimePeakProgress: nil
        )
    }

}

private protocol LocalCodexSessionTokenUsageDiskCaching {
    func readEntry(
        covering period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        isUsable: (TokenUsageCacheEntry) -> Bool
    ) -> TokenUsageCacheEntry?
    func writeEntry(_ entry: TokenUsageCacheEntry)
}

private struct TokenUsageCacheEntry: Codable, Equatable {
    var period: CodexTokenUsagePeriod
    var generatedAt: Date
    var buckets: [CodexDailyTokenUsage]
    var allTimePeak: CodexDailyTokenUsage?
    var allTimePeakCoversAllHistory: Bool?

    var hasAllTimePeak: Bool {
        allTimePeak != nil && allTimePeakCoversAllHistory == true
    }

    func coversCurrentWindow(
        for period: CodexTokenUsagePeriod,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard buckets.count >= period.dayCount,
              let firstDay = buckets.first?.day,
              let lastDay = buckets.last?.day
        else {
            return false
        }

        let today = calendar.startOfDay(for: now)
        let firstRequiredDay = calendar.date(
            byAdding: .day,
            value: 1 - period.dayCount,
            to: today
        ) ?? today

        return firstDay <= firstRequiredDay && lastDay == today
    }
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

    func readEntry(
        covering period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        isUsable: (TokenUsageCacheEntry) -> Bool
    ) -> TokenUsageCacheEntry? {
        readPayload()?.entries.values
            .filter { $0.period.dayCount >= period.dayCount }
            .filter { peakScope == .currentPeriod || $0.hasAllTimePeak }
            .filter(isUsable)
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
