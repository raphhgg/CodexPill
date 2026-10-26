import Foundation

/// Cursor plan usage for the menu, read from Cursor's live sign-in once the user connects it.
struct CursorUsage: ProviderConnection {
    let provider = UsageProvider.cursor
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: SettingsCell<CursorSettings>
    let client: CursorUsageClient
    /// Daily tokens for the Token Usage card, read from the same sign-in.
    let tokenUsageClient: CursorTokenUsageClient?

    init(
        settings: SettingsCell<CursorSettings>,
        client: CursorUsageClient,
        tokenUsageClient: CursorTokenUsageClient? = nil,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.tokenUsageClient = tokenUsageClient
        self.refreshInterval = refreshInterval
    }

    func connect() async {
        settings.update { $0.isConnected = true }
    }

    var isConnected: Bool {
        settings.value.isConnected
    }

    var isShown: Bool {
        settings.value.isShown
    }

    func setShown(_ isShown: Bool) {
        settings.update { $0.isShown = isShown }
    }

    func disconnect() async {
        settings.update { $0.isConnected = false }
    }

    func readUsage(now _: Date) async -> UsageProviderReading {
        guard settings.value.isConnected else { return .notConnected }
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
            credits: snapshot.onDemand.map { .extraUsage(spent: $0.usedUSD, limit: $0.limitUSD, currencyCode: "USD") },
            accountEmail: snapshot.accountEmail
        )
    }
}
