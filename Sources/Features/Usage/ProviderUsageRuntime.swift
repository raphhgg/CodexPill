import Foundation
import OSLog

private let providerUsageLogger = Logger(subsystem: "com.raphhgg.refill", category: "ProviderUsage")

/// Owns every connected tool other than Codex: reads each at most once per its `refreshInterval`, keeps its latest
/// reading and its last good snapshot for the menu, and runs the actions the menu sends.
///
/// Refill never renews a tool's own sign-in. When it expires or goes away, the tool's card asks the user to open the
/// tool, or to sign in with Refill's own sign-in where the tool offers one.
@MainActor
final class ProviderUsageRuntime {
    nonisolated static let refreshInterval: TimeInterval = 5 * 60

    private let connections: [any ProviderConnection]
    private let now: () -> Date
    private let onChange: () -> Void
    private var readings: [UsageProvider: UsageProviderReading] = [:]
    private var lastSnapshots: [UsageProvider: UsageSnapshot] = [:]
    private var lastRefreshStartedAt: [UsageProvider: Date] = [:]

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

    /// Runs `action` for one tool, then reads that tool again. Returns what the user should be told, if anything.
    @discardableResult
    func perform(_ action: ProviderAction, on provider: UsageProvider) async -> ProviderNotice? {
        guard let connection = connection(for: provider) else { return nil }
        var notice: ProviderNotice?
        switch action {
        case .connect, .allowKeychainAccess:
            await connection.connect()
        case .disconnect:
            await connection.disconnect()
        case .signIn, .signOut:
            do throws(ProviderNotice) {
                if action == .signIn {
                    try await connection.signIn()
                } else {
                    try await connection.signOut()
                }
            } catch {
                notice = error
            }
            // The account may have changed, so the last numbers may belong to another one.
            readings[provider] = nil
            lastSnapshots[provider] = nil
        case .switchAccount, .addAccount, .removeAccount, .useResetCredit:
            return nil
        }
        await refreshIfDue(forcing: provider)
        return notice
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
                Self.logSignInLoss(of: provider, from: readings[provider], to: reading)
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

    /// Logs the moment a tool's sign-in expires or goes away, with the reason's category only.
    private static func logSignInLoss(of provider: UsageProvider, from previous: UsageProviderReading?, to reading: UsageProviderReading) {
        guard reading != previous, case let .unavailable(reason) = reading else { return }
        let name = provider.copy.name
        switch reason {
        case .signedOut: providerUsageLogger.notice("\(name, privacy: .public) is now signed out")
        case .signInExpired: providerUsageLogger.notice("\(name, privacy: .public) sign-in is now expired")
        case .signInRequired: providerUsageLogger.notice("\(name, privacy: .public) now needs a new sign-in")
        default: break
        }
    }
}
