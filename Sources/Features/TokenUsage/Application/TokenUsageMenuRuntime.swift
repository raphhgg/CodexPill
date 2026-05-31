import Foundation

private let tokenUsageMenuDefaultFreshnessInterval: TimeInterval = 15 * 60

@MainActor
final class TokenUsageMenuRuntime: Sendable {
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
        let relay = TokenUsageMenuRefreshRelay(runtime: self, request: request)
        refreshTask = Task.detached { [provider, relay, request] in
            // Keep the filesystem scan independent from the transient menu view.
            let loadState = await provider.load(
                period: request.period,
                peakScope: request.peakScope,
                forceRefresh: forceRefresh
            ) { progress in
                relay.update(progress)
            }
            guard !Task.isCancelled else { return }
            await relay.finish(loadState)
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

    fileprivate func updateProgress(_ progress: TokenUsageScanProgress, request: TokenUsageMenuLoadRequest) {
        guard refreshRequest == request else { return }

        if case .loaded(var data) = loadState {
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

    fileprivate func finishRefresh(_ loadState: TokenUsageMenuLoadState, request: TokenUsageMenuLoadRequest) {
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

private final class TokenUsageMenuRefreshRelay: @unchecked Sendable {
    private weak var runtime: TokenUsageMenuRuntime?
    private let request: TokenUsageMenuLoadRequest

    init(runtime: TokenUsageMenuRuntime, request: TokenUsageMenuLoadRequest) {
        self.runtime = runtime
        self.request = request
    }

    func update(_ progress: TokenUsageScanProgress) {
        Task { @MainActor [weak runtime, request] in
            runtime?.updateProgress(progress, request: request)
        }
    }

    @MainActor
    func finish(_ loadState: TokenUsageMenuLoadState) {
        runtime?.finishRefresh(loadState, request: request)
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

protocol TokenUsageMenuProviding: Sendable {
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
        now: @escaping @Sendable () -> Date = Date.init,
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
    private let refreshPolicy: TokenUsageCacheBackedRefreshPolicy
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var cachedEntriesByPeriod: [CodexTokenUsagePeriod: TokenUsageCacheEntry] = [:]

    init(
        scanner: CodexSessionTokenUsageScanner,
        sessionsDirectory: URL,
        diskCache: LocalCodexSessionTokenUsageDiskCaching,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar
    ) {
        self.scanner = scanner
        self.sessionsDirectory = sessionsDirectory
        self.diskCache = diskCache
        refreshPolicy = TokenUsageCacheBackedRefreshPolicy(calendar: calendar)
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
        if !forceRefresh, let entry = refreshPolicy.displayEntry(
            from: Array(cachedEntriesByPeriod.values),
            covering: period,
            peakScope: peakScope,
            now: referenceDate
        ) {
            return .loaded(loadedData(from: entry, for: period))
        }

        if !forceRefresh, let entry = diskCache.readEntry(
            covering: period,
            peakScope: peakScope,
            isUsable: { refreshPolicy.canDisplay($0, for: period, peakScope: peakScope, now: referenceDate) }
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
            let referenceDate = now()
            let previousEntry = cachedRefreshEntry(covering: period, peakScope: peakScope, now: referenceDate)
            let result = try scanSelectedPeriod(
                period: period,
                referenceDate: referenceDate,
                previousEntry: previousEntry,
                progress: progress
            )
            let cachedPeak = cachedAllTimePeak() ?? previousEntry?.allTimePeak ?? persistedAllTimePeak(for: period, now: referenceDate)
            let refreshedAllTimePeak = peakScope == .allTime && cachedPeak == nil
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
                fileContributions: result.fileContributions,
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

    private func scanSelectedPeriod(
        period: CodexTokenUsagePeriod,
        referenceDate: Date,
        previousEntry: TokenUsageCacheEntry?,
        progress: @escaping @Sendable (TokenUsageScanProgress) -> Void
    ) throws -> CodexSessionTokenUsageScanResult {
        guard let previousEntry,
              let fileContributions = previousEntry.fileContributions,
              previousEntry.overlapsCurrentWindow(for: period, now: referenceDate, calendar: calendar)
        else {
            return try scanner.scan(
                sessionsDirectory: sessionsDirectory,
                period: period,
                now: referenceDate,
                progress: progress
            )
        }

        return try scanner.scanIncremental(
            sessionsDirectory: sessionsDirectory,
            period: period,
            now: referenceDate,
            cachedFileContributions: fileContributions,
            progress: progress
        )
    }

    private func cachedAllTimePeak() -> CodexDailyTokenUsage? {
        refreshPolicy.allTimePeak(from: Array(cachedEntriesByPeriod.values))
    }

    private func persistedAllTimePeak(for period: CodexTokenUsagePeriod, now: Date) -> CodexDailyTokenUsage? {
        guard let entry = diskCache.readEntry(
            covering: period,
            peakScope: .allTime,
            isUsable: { refreshPolicy.canDisplay($0, for: period, peakScope: .allTime, now: now) }
        ) else {
            return nil
        }
        cachedEntriesByPeriod[entry.period] = entry
        return entry.allTimePeak
    }

    private func cachedRefreshEntry(
        covering period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        now: Date
    ) -> TokenUsageCacheEntry? {
        let cachedEntry = refreshPolicy.refreshSeedEntry(
            from: Array(cachedEntriesByPeriod.values),
            covering: period,
            peakScope: peakScope,
            now: now
        )
        if let entry = cachedEntry {
            return entry
        }

        guard let entry = diskCache.readEntry(
            covering: period,
            peakScope: peakScope,
            isUsable: { refreshPolicy.canSeedRefresh($0, for: period, peakScope: peakScope, now: now) }
        ) else {
            return nil
        }
        cachedEntriesByPeriod[entry.period] = entry
        return entry
    }

    private func loadedData(from entry: TokenUsageCacheEntry, for period: CodexTokenUsagePeriod) -> TokenUsageMenuLoadedData {
        TokenUsageMenuLoadedData(
            buckets: Array(entry.buckets.suffix(period.dayCount)),
            allTimePeak: entry.allTimePeak,
            allTimePeakProgress: nil
        )
    }

}

private protocol LocalCodexSessionTokenUsageDiskCaching: Sendable {
    func readEntry(
        covering period: CodexTokenUsagePeriod,
        peakScope: TokenUsagePeakScope,
        isUsable: (TokenUsageCacheEntry) -> Bool
    ) -> TokenUsageCacheEntry?
    func writeEntry(_ entry: TokenUsageCacheEntry)
}

private struct LocalCodexSessionTokenUsageDiskCache: LocalCodexSessionTokenUsageDiskCaching, @unchecked Sendable {
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
