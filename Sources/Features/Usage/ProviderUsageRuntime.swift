import Foundation

/// Owns every connected tool other than Codex: reads each at most once per its `refreshInterval`, keeps its latest
/// reading, its last good snapshot and its saved accounts for the menu, and runs the actions the menu sends.
@MainActor
final class ProviderUsageRuntime {
    nonisolated static let refreshInterval: TimeInterval = 5 * 60

    private let connections: [any ProviderConnection]
    private let now: () -> Date
    private let onChange: () -> Void
    private var readings: [UsageProvider: UsageProviderReading] = [:]
    private var lastSnapshots: [UsageProvider: UsageSnapshot] = [:]
    private var accounts: [UsageProvider: [ProviderAccount]] = [:]
    private var lastRefreshStartedAt: [UsageProvider: Date] = [:]
    private var signingIn: Set<UsageProvider> = []
    /// Bumped when a tool's signed-in account changes, so a read that started before the change is dropped.
    private var generations: [UsageProvider: Int] = [:]

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

    /// Tools read at least once, in registration order, with staleness judged now.
    var states: [ProviderUsageState] {
        let date = now()
        return connections.compactMap { connection in
            let provider = connection.provider
            let reading = readings[provider] ?? (signingIn.contains(provider) ? .notConnected : nil)
            return reading.map {
                ProviderUsageState(
                    provider: provider,
                    status: ProviderUsageStatus(
                        $0,
                        lastSnapshot: lastSnapshots[provider],
                        at: date,
                        staleAfter: connection.staleAfter
                    ),
                    accounts: accounts[provider] ?? [],
                    isSigningIn: signingIn.contains(provider),
                    canSignIn: connection.signIn != nil
                )
            }
        }
    }

    func connection(for provider: UsageProvider) -> (any ProviderConnection)? {
        connections.first { $0.provider == provider }
    }

    /// Runs `action` for one tool, then reads that tool again. Returns what to tell the user when it failed.
    /// Switching or signing in drops the tool's reading first, so the previous account's numbers never show.
    func perform(_ action: ProviderAction, on provider: UsageProvider) async -> ProviderNotice? {
        guard let connection = connection(for: provider) else { return nil }
        var notice: ProviderNotice?
        do {
            switch action {
            case .connect, .allowKeychainAccess:
                if await !connection.connect() {
                    try await signIn(on: connection)
                }
            case .disconnect:
                await connection.disconnect()
            case let .switchAccount(id):
                discardReading(for: provider)
                defer { discardReading(for: provider) }
                try await connection.switchAccount(to: id)
            case .addAccount:
                try await connection.addCurrentAccount()
            case let .removeAccount(id):
                try await connection.removeAccount(id)
            case .signIn:
                try await signIn(on: connection)
            case .cancelSignIn:
                await connection.signIn?.cancel()
                return nil
            case .useResetCredit:
                return nil
            }
        } catch {
            notice = error
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

        let startGenerations = generations
        for connection in dueConnections {
            lastRefreshStartedAt[connection.provider] = startedAt
        }
        await withTaskGroup(of: (UsageProvider, UsageProviderReading, [ProviderAccount]?).self) { group in
            for connection in dueConnections {
                group.addTask {
                    let reading = await connection.readUsage(now: startedAt)
                    guard reading != .notConnected else { return (connection.provider, reading, []) }
                    // A list that can't be read keeps the last one rather than looking like no saved accounts.
                    return (connection.provider, reading, try? await connection.savedAccounts())
                }
            }
            for await (provider, reading, savedAccounts) in group
            where generations[provider] == startGenerations[provider] {
                readings[provider] = reading
                if let savedAccounts {
                    accounts[provider] = savedAccounts
                }
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

    /// Runs the tool's browser sign-in, one at a time. The card shows it while it waits for the user.
    private func signIn(on connection: any ProviderConnection) async throws(ProviderNotice) {
        let provider = connection.provider
        guard let signIn = connection.signIn, signingIn.insert(provider).inserted else { return }
        onChange()
        defer { signingIn.remove(provider) }
        if try await signIn.run() {
            discardReading(for: provider)
        }
    }

    private func discardReading(for provider: UsageProvider) {
        generations[provider, default: 0] += 1
        lastSnapshots[provider] = nil
        if readings[provider] != nil {
            readings[provider] = .awaitingUsage
        }
        onChange()
    }
}
