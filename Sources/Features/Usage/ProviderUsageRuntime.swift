import Foundation

/// Reads non-Codex providers at most once per their `refreshInterval` each and keeps their latest reading for the menu.
@MainActor
final class ProviderUsageRuntime {
    nonisolated static let refreshInterval: TimeInterval = 5 * 60

    private let sources: [any UsageProviderSource]
    private let now: () -> Date
    private let onChange: () -> Void
    private var readings: [UsageProvider: UsageProviderReading] = [:]
    private var lastRefreshStartedAt: [UsageProvider: Date] = [:]

    init(
        sources: [any UsageProviderSource],
        now: @escaping () -> Date = Date.init,
        onChange: @escaping () -> Void
    ) {
        precondition(!sources.contains { $0.provider == .codex }, "Codex usage comes from CodexAccount, not a provider source")
        self.sources = sources
        self.now = now
        self.onChange = onChange
    }

    /// Providers read at least once, in registration order, with staleness judged now.
    var states: [ProviderUsageState] {
        let date = now()
        return sources.compactMap { source in
            readings[source.provider].map {
                ProviderUsageState(
                    provider: source.provider,
                    status: ProviderUsageStatus($0, at: date, staleAfter: source.staleAfter)
                )
            }
        }
    }

    func refreshIfDue() async {
        let startedAt = now()
        let dueSources = sources.filter { source in
            guard let last = lastRefreshStartedAt[source.provider] else { return true }
            return startedAt.timeIntervalSince(last) >= source.refreshInterval
        }
        guard !dueSources.isEmpty else { return }

        for source in dueSources {
            lastRefreshStartedAt[source.provider] = startedAt
        }
        await withTaskGroup(of: (UsageProvider, UsageProviderReading).self) { group in
            for source in dueSources {
                group.addTask { (source.provider, await source.readUsage(now: startedAt)) }
            }
            for await (provider, reading) in group {
                readings[provider] = reading
            }
        }
        onChange()
    }
}
