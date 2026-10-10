import Foundation

/// Cursor plan usage for the menu, read only after the user connects Cursor.
struct CursorUsage: ProviderConnection {
    let provider = UsageProvider.cursor
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: CursorUsageSettingsStore
    let client: CursorUsageClient
    /// Saved Cursor sign-ins to switch between. Nil in isolated runs, which never quit the real Cursor.
    let accounts: CursorAccounts?

    init(
        settings: CursorUsageSettingsStore,
        client: CursorUsageClient,
        accounts: CursorAccounts? = nil,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.accounts = accounts
        self.refreshInterval = refreshInterval
    }

    func connect() async {
        settings.isEnabled = true
    }

    func disconnect() async {
        settings.isEnabled = false
    }

    let signIn: (any ProviderSignIn)? = nil

    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount] {
        guard let accounts else { return [] }
        do {
            let activeID = try accounts.activeAccountID()
            return try accounts.savedAccounts().map { ProviderAccount(id: $0.id, email: $0.email, isActive: $0.id == activeID) }
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

    func addCurrentAccount() async throws(ProviderNotice) {
        do {
            try store().captureCurrent()
        } catch {
            throw error.notice
        }
    }

    func removeAccount(_ id: UUID) async throws(ProviderNotice) {
        do {
            try store().remove(id)
        } catch {
            throw error.notice
        }
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
