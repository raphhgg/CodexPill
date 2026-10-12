import Foundation

/// Owns every connected tool other than Codex: reads each at most once per its `refreshInterval`, keeps its latest
/// reading and its last good snapshot for the menu, and runs the actions the menu sends.
///
/// A tool's expired live sign-in is renewed by the tool itself, one renewal at a time.
@MainActor
final class ProviderUsageRuntime {
    nonisolated static let refreshInterval: TimeInterval = 5 * 60

    private let connections: [any ProviderConnection]
    private let now: () -> Date
    private let onChange: () -> Void
    private var readings: [UsageProvider: UsageProviderReading] = [:]
    private var lastSnapshots: [UsageProvider: UsageSnapshot] = [:]
    private var lastRefreshStartedAt: [UsageProvider: Date] = [:]
    private var isRenewingLiveSignIns = false

    init(
        connections: [any ProviderConnection],
        now: @escaping () -> Date = Date.init,
        onChange: @escaping () -> Void
    ) {
        precondition(!connections.contains { $0.provider == .codex }, "Codex usage comes from CodexAccount, not a provider connection")
        self.connections = connections
        self.now = now
        self.onChange = onChange
    }

    /// Tools read at least once or connected, in registration order, with staleness judged now. A connected tool
    /// waits for its first read instead of looking unconnected.
    var states: [ProviderUsageState] {
        let date = now()
        return connections.compactMap { connection in
            let provider = connection.provider
            let reading = readings[provider] ?? (connection.isConnected ? .awaitingUsage : nil)
            return reading.map {
                ProviderUsageState(
                    provider: provider,
                    status: ProviderUsageStatus(
                        $0,
                        lastSnapshot: lastSnapshots[provider],
                        at: date,
                        staleAfter: connection.staleAfter
                    )
                )
            }
        }
    }

    var hasConnectedTool: Bool {
        connections.contains(where: \.isConnected)
    }

    func connection(for provider: UsageProvider) -> (any ProviderConnection)? {
        connections.first { $0.provider == provider }
    }

    /// Runs `action` for one tool, then reads that tool again.
    func perform(_ action: ProviderAction, on provider: UsageProvider) async {
        guard let connection = connection(for: provider) else { return }
        switch action {
        case .connect, .allowKeychainAccess:
            await connection.connect()
        case .disconnect:
            await connection.disconnect()
        case .switchAccount, .addAccount, .removeAccount, .useResetCredit:
            return
        }
        await refreshIfDue(forcing: provider)
    }

    /// `forcing` reads that tool even inside its interval, for example right after the user connects it.
    func refreshIfDue(forcing forcedProvider: UsageProvider? = nil) async {
        let startedAt = now()
        let dueConnections = connections.filter { connection in
            guard connection.provider != forcedProvider, let last = lastRefreshStartedAt[connection.provider] else { return true }
            return startedAt.timeIntervalSince(last) >= connection.refreshInterval
        }
        guard !dueConnections.isEmpty else { return }

        for connection in dueConnections {
            lastRefreshStartedAt[connection.provider] = startedAt
        }
        await withTaskGroup(of: (UsageProvider, UsageProviderReading).self) { group in
            for connection in dueConnections {
                group.addTask { (connection.provider, await connection.readUsage(now: startedAt)) }
            }
            for await (provider, reading) in group {
                readings[provider] = reading
                switch reading {
                case let .snapshot(snapshot):
                    lastSnapshots[provider] = snapshot
                case let .unavailable(reason) where reason.keepsLastSnapshot:
                    break
                case .notConnected, .unavailable, .awaitingUsage:
                    lastSnapshots[provider] = nil
                }
            }
        }
        onChange()
    }

    /// Lets each tool whose last read found its sign-in expired renew it, then reads again every tool that renewed.
    func renewLiveSignInsIfNeeded() async {
        let expired = connections.filter { readings[$0.provider] == .unavailable(.signInExpired) }
        guard !expired.isEmpty, !isRenewingLiveSignIns else { return }
        isRenewingLiveSignIns = true
        var renewed: [UsageProvider] = []
        for connection in expired where await connection.renewLiveSignInIfNeeded(now: now()) {
            renewed.append(connection.provider)
        }
        isRenewingLiveSignIns = false
        for provider in renewed {
            await refreshIfDue(forcing: provider)
        }
    }
}
