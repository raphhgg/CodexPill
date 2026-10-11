import Foundation

/// Owns every connected tool other than Codex: reads each at most once per its `refreshInterval`, keeps its latest
/// reading, its last good snapshot and its saved accounts for the menu, and runs the actions the menu sends.
///
/// Saved accounts the tool is not signed in to are read every `inactiveRefreshInterval`, one at a time, the way
/// `AccountsController` reads inactive Codex accounts. An action that changes accounts first lets the account being
/// read finish and stops the rest, so a renewed sign-in is saved before the action touches any sign-in.
///
/// A tool's expired live sign-in is renewed by the tool itself, one renewal at a time, never during a sign-in, an
/// account action or the inactive pass. Account actions wait for it, so they save the renewed sign-in.
///
/// After each read, a connected tool's live account is saved when it is not saved yet. That save waits for the same
/// work a renewal waits for, and account actions wait for it.
@MainActor
final class ProviderUsageRuntime {
    nonisolated static let refreshInterval: TimeInterval = 5 * 60
    nonisolated static let inactiveRefreshInterval: TimeInterval = 15 * 60

    private let connections: [any ProviderConnection]
    private let now: () -> Date
    private let onChange: () -> Void
    private var readings: [UsageProvider: UsageProviderReading] = [:]
    private var lastSnapshots: [UsageProvider: UsageSnapshot] = [:]
    private var accounts: [UsageProvider: [ProviderAccount]] = [:]
    private var lastRefreshStartedAt: [UsageProvider: Date] = [:]
    private var signIns: [UsageProvider: Task<Result<Bool, ProviderNotice>, Never>] = [:]
    /// Bumped when a tool's signed-in account changes, so a read that started before the change is dropped.
    private var generations: [UsageProvider: Int] = [:]
    private var lastInactiveRefreshStartedAt: Date?
    private var inactiveRefresh: Task<Void, Never>?
    private var stopsInactiveRefresh = false
    private var liveRenewal: Task<[UsageProvider], Never>?
    private var liveAccountSave: Task<[UsageProvider], Never>?
    private var accountActionsInFlight = 0

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
                    ),
                    accounts: accounts[provider] ?? [],
                    isSigningIn: signIns[provider] != nil,
                    signInAvailability: connection.signInAvailability
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

    /// Runs `action` for one tool, then reads that tool again. Returns what to tell the user when it failed.
    /// Switching drops the tool's reading first, so the previous account's numbers never show.
    func perform(_ action: ProviderAction, on provider: UsageProvider) async -> ProviderNotice? {
        guard let connection = connection(for: provider) else { return nil }
        var readsNewAccounts = false
        var notice: ProviderNotice?
        do {
            switch action {
            case .connect, .allowKeychainAccess:
                await connection.connect()
            case .disconnect:
                await connection.disconnect()
            case let .switchAccount(id):
                guard signIns[provider] == nil else { return ProviderCopy.switchDuringSignIn }
                accountActionsInFlight += 1
                defer { accountActionsInFlight -= 1 }
                await finishSignInWork()
                discardReading(for: provider)
                defer { discardReading(for: provider) }
                try await connection.switchAccount(to: id)
            case .addAccount:
                guard signIns[provider] == nil else { return nil }
                let signIn = Task { () -> Result<Bool, ProviderNotice> in
                    await finishSignInWork()
                    do throws(ProviderNotice) {
                        return .success(try await connection.addAccount())
                    } catch {
                        return .failure(error)
                    }
                }
                signIns[provider] = signIn
                onChange()
                let result = await signIn.value
                signIns[provider] = nil
                readsNewAccounts = (try result.get())
            case let .removeAccount(id):
                accountActionsInFlight += 1
                defer { accountActionsInFlight -= 1 }
                await finishSignInWork()
                try await connection.removeAccount(id)
            case .cancelSignIn:
                signIns[provider]?.cancel()
                return nil
            case .useResetCredit:
                return nil
            }
        } catch {
            notice = error
        }
        await refreshIfDue(forcing: provider)
        if readsNewAccounts {
            await refreshInactiveAccounts(of: connection, onlyUnread: true)
        }
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
        await saveNewLiveAccounts(of: dueConnections.filter(\.isConnected))
        onChange()
    }

    /// Reads every connected tool's inactive saved accounts, at most once per `inactiveRefreshInterval`. It waits
    /// while a sign-in or an account action runs, since either may change the accounts it would read.
    func refreshInactiveAccountsIfDue() async {
        guard !isChangingSignIns else { return }
        let startedAt = now()
        if let lastInactiveRefreshStartedAt, startedAt.timeIntervalSince(lastInactiveRefreshStartedAt) < Self.inactiveRefreshInterval {
            return
        }
        lastInactiveRefreshStartedAt = startedAt
        for connection in connections where connection.isConnected {
            await refreshInactiveAccounts(of: connection, onlyUnread: false)
        }
    }

    /// Lets each tool whose last read found its sign-in expired renew it, then reads again every tool that renewed.
    func renewLiveSignInsIfNeeded() async {
        let expired = connections.filter { readings[$0.provider] == .unavailable(.signInExpired) }
        guard !expired.isEmpty, !isChangingSignIns else { return }
        let renewal = Task { [now] in
            var renewed: [UsageProvider] = []
            for connection in expired {
                if await connection.renewLiveSignInIfNeeded(now: now()) {
                    renewed.append(connection.provider)
                }
            }
            return renewed
        }
        liveRenewal = renewal
        let renewed = await renewal.value
        liveRenewal = nil
        for provider in renewed {
            await refreshIfDue(forcing: provider)
        }
    }

    private var isChangingSignIns: Bool {
        !signIns.isEmpty || accountActionsInFlight > 0 || inactiveRefresh != nil || liveRenewal != nil || liveAccountSave != nil
    }

    private func saveNewLiveAccounts(of connected: [any ProviderConnection]) async {
        guard !connected.isEmpty, !isChangingSignIns else { return }
        let save = Task {
            var saved: [UsageProvider] = []
            for connection in connected where await connection.saveLiveAccountIfNew() {
                saved.append(connection.provider)
            }
            return saved
        }
        liveAccountSave = save
        let saved = await save.value
        liveAccountSave = nil
        for provider in saved {
            if let updated = try? await connection(for: provider)?.savedAccounts() {
                accounts[provider] = updated
            }
        }
    }

    /// `onlyUnread` reads only accounts with no limits yet, such as one the user just added.
    private func refreshInactiveAccounts(of connection: any ProviderConnection, onlyUnread: Bool) async {
        guard inactiveRefresh == nil else { return }
        let provider = connection.provider
        let refresh = Task {
            guard let saved = try? await connection.savedAccounts() else { return }
            for account in saved where !account.isActive && (!onlyUnread || account.usage == nil) {
                guard !stopsInactiveRefresh else { return }
                await connection.refreshInactiveAccount(account.id, now: now())
            }
        }
        inactiveRefresh = refresh
        let startGeneration = generations[provider]
        await refresh.value
        inactiveRefresh = nil
        if generations[provider] == startGeneration, let updated = try? await connection.savedAccounts() {
            accounts[provider] = updated
            onChange()
        }
    }

    /// Lets a live renewal, a live account save and the account being read finish, so a renewed sign-in is saved
    /// before an action touches any sign-in.
    private func finishSignInWork() async {
        _ = await liveRenewal?.value
        _ = await liveAccountSave?.value
        guard let inactiveRefresh else { return }
        stopsInactiveRefresh = true
        await inactiveRefresh.value
        stopsInactiveRefresh = false
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
