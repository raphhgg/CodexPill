import Foundation

/// Cursor plan usage for the menu, read only after the user connects Cursor.
struct CursorUsage: UsageProviderSource {
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

    func connect() {
        settings.isEnabled = true
    }

    func disconnect() {
        settings.isEnabled = false
    }

    /// Signs Cursor in to a saved account. Cursor quits and reopens, so ask the user first.
    func switchAccount(to id: UUID) async throws(CursorAccountsError) {
        guard let accounts else { throw .switchingUnavailable }
        try await accounts.activate(id)
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
