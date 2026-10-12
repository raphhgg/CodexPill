import Foundation

/// Cursor plan usage for the menu, and the Cursor accounts Refill saved. The card reads Cursor's live sign-in once
/// the user connects it; each saved account is read with its own saved sign-in.
struct CursorUsage: ProviderConnection {
    let provider = UsageProvider.cursor
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: CursorUsageSettingsStore
    let client: CursorUsageClient
    /// Saved Cursor sign-ins to switch between. Nil in isolated runs, which never quit the real Cursor.
    let accounts: CursorAccounts?
    /// Cursor's own sign-in in a separate window. Nil when this build can't add accounts.
    let login: CursorIsolatedLogin?
    /// Daily tokens for the Token Usage card, read from the same sign-in.
    let tokenUsageClient: CursorTokenUsageClient?

    init(
        settings: CursorUsageSettingsStore,
        client: CursorUsageClient,
        tokenUsageClient: CursorTokenUsageClient? = nil,
        accounts: CursorAccounts? = nil,
        login: CursorIsolatedLogin? = nil,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.accounts = accounts
        self.login = login
        self.tokenUsageClient = tokenUsageClient
        self.refreshInterval = refreshInterval
    }

    func connect() async {
        settings.isEnabled = true
    }

    var isConnected: Bool {
        settings.isEnabled
    }

    func disconnect() async {
        settings.isEnabled = false
    }

    var signInAvailability: ProviderSignInAvailability {
        guard accounts != nil, let login else { return .unsupported }
        return login.isInstalled ? .available : .notInstalled
    }

    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount] {
        guard let accounts else { return [] }
        do {
            let activeID = try accounts.activeAccountID()
            return try accounts.savedAccounts().map {
                ProviderAccount(id: $0.id, email: $0.email, isActive: $0.id == activeID, usage: $0.usage.map(Self.usage(from:)))
            }
        } catch {
            throw error.notice
        }
    }

    /// Signs Cursor in to a saved account. Cursor quits and reopens, so the menu asks first.
    func switchAccount(to id: UUID) async throws(ProviderNotice) {
        do {
            try await store().activate(id)
        } catch {
            throw error.notice
        }
    }

    func saveLiveAccountIfNew() async -> Bool {
        guard settings.isEnabled, let accounts else { return false }
        return ((try? accounts.saveCurrentIfNew()) ?? nil) != nil
    }

    /// Signs in through Cursor's own sign-in in a separate window with a throwaway profile, and saves the account.
    /// Cursor's live sign-in is not touched; switching to the new account later works like any saved account.
    func addAccount() async throws(ProviderNotice) -> Bool {
        let store: CursorAccounts
        do {
            store = try self.store()
        } catch {
            throw error.notice
        }
        guard let login else { throw CursorAccountsError.switchingUnavailable.notice }

        let signIn: CursorSignIn
        do {
            signIn = try await login.signIn()
        } catch {
            if error == .cancelled { return false }
            throw error.notice
        }
        do {
            try store.add(signIn)
        } catch {
            throw error.notice
        }
        settings.isEnabled = true
        return true
    }

    func removeAccount(_ id: UUID) async throws(ProviderNotice) {
        do {
            try store().remove(id)
        } catch {
            throw error.notice
        }
    }

    /// Cursor renews a token only while it runs with that profile, so Refill never renews a saved sign-in. Once its
    /// token expires, the account keeps its last limits, which the menu shows as stale.
    func refreshInactiveAccount(_ id: UUID, now _: Date) async {
        guard let accounts, (try? accounts.activeAccountID()) != id, let account = try? accounts.savedAccount(id) else { return }
        guard case let .available(snapshot) = await client.refresh(savedSignIn: account.signIn) else { return }
        accounts.recordUsage(snapshot, for: id, ifSignInUnchangedFrom: account.signIn)
    }

    private func store() throws(CursorAccountsError) -> CursorAccounts {
        guard let accounts else { throw .switchingUnavailable }
        return accounts
    }

    func readUsage(now _: Date) async -> UsageProviderReading {
        guard settings.isEnabled else { return .notConnected }
        return Self.reading(from: await client.refresh())
    }

    static func reading(from status: CursorUsageStatus) -> UsageProviderReading {
        switch status {
        case .cursorNotInstalled: .unavailable(.notInstalled)
        case .signedOut: .unavailable(.signedOut)
        case .tokenExpired, .unauthorized: .unavailable(.signInExpired)
        case .unavailable(.localStateUnreadable): .unavailable(.signInUnreadable)
        case .unavailable(.localStateBusy): .unavailable(.signInBusy)
        case .unavailable(.network): .unavailable(.unreachable)
        case .unavailable(.forbidden): .unavailable(.accessDenied)
        case .unavailable(.rateLimited): .unavailable(.rateLimited)
        case .unavailable(.serviceError): .unavailable(.serviceError)
        case .unavailable(.unexpectedResponse): .unavailable(.unexpectedResponse)
        case let .available(snapshot): .snapshot(usage(from: snapshot))
        }
    }

    static func usage(from snapshot: CursorUsageSnapshot) -> UsageSnapshot {
        let windows = snapshot.includedUsagePercent.map { percent in
            [UsageWindow(
                kind: .billingCycle,
                usedPercent: Int(percent.rounded()),
                resetsAt: snapshot.billingCycle?.end,
                durationMinutes: snapshot.billingCycle.map { Int($0.duration / 60) }
            )]
        } ?? []
        return UsageSnapshot(
            provider: .cursor,
            planName: snapshot.planName,
            windows: windows,
            fetchedAt: snapshot.fetchedAt,
            spend: snapshot.onDemand.map { UsageSpend(usedUSD: $0.usedUSD, limitUSD: $0.limitUSD) }
        )
    }
}
