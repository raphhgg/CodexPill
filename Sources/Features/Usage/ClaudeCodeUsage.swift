import Foundation

/// Claude Code subscription limits for the menu, read from Claude Code's sign-in only after the user connects it.
struct ClaudeCodeUsage: UsageProviderSource {
    let provider = UsageProvider.claude
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: ClaudeUsageSettingsStore
    let client: ClaudeUsageClient
    /// Saved Claude Code sign-ins to switch between. Nil in isolated runs, which never write the real Keychain.
    let accounts: ClaudeCodeAccountStore?

    init(
        settings: ClaudeUsageSettingsStore,
        client: ClaudeUsageClient,
        accounts: ClaudeCodeAccountStore? = nil,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.accounts = accounts
        self.refreshInterval = refreshInterval
    }

    /// Turns the feature on and lets the next read ask for Keychain access, since the user just chose to connect.
    func connect() async {
        settings.isEnabled = true
        await client.allowKeychainPromptOnNextRead()
    }

    func allowKeychainAccess() async {
        await client.allowKeychainPromptOnNextRead()
    }

    /// Signs Claude Code in to a saved account. The switch rewrote Claude Code's sign-in, which can reset its Keychain
    /// access rule, so the next read may show the Keychain prompt: the user just asked for this.
    func switchAccount(to id: UUID) async throws(ClaudeCodeAccountError) {
        guard let accounts else { throw .switchingUnavailable }
        try accounts.activate(id)
        await client.allowKeychainPromptOnNextRead()
    }

    func disconnect() {
        settings.isEnabled = false
    }

    func readUsage(now: Date) async -> UsageProviderReading {
        guard settings.isEnabled else { return .notConnected }
        return Self.reading(from: await client.refresh(now: now), fetchedAt: now)
    }

    static func reading(from status: ClaudeUsageStatus, fetchedAt: Date) -> UsageProviderReading {
        switch status {
        case .signedOut: return .unavailable(.signedOut)
        case .keychainAccessNeeded: return .unavailable(.keychainAccessNeeded)
        case .signInUnreadable: return .unavailable(.signInUnreadable)
        case .signInExpired: return .unavailable(.signInExpired)
        case .forbidden: return .unavailable(.accessDenied)
        case .rateLimited: return .unavailable(.rateLimited)
        case .unreachable: return .unavailable(.unreachable)
        case .serviceError: return .unavailable(.serviceError)
        case .unexpectedResponse: return .unavailable(.unexpectedResponse)
        case let .available(report, planName):
            let windows = [
                report.fiveHour.map { usageWindow(.session, $0, durationMinutes: 300) },
                report.sevenDay.map { usageWindow(.weekly, $0, durationMinutes: 10_080) },
            ].compactMap(\.self)
            guard !windows.isEmpty else { return .awaitingUsage }
            return .snapshot(UsageSnapshot(provider: .claude, planName: planName, windows: windows, fetchedAt: fetchedAt))
        }
    }

    private static func usageWindow(_ kind: UsageWindowKind, _ window: ClaudeUsageReport.Window, durationMinutes: Int) -> UsageWindow {
        UsageWindow(
            kind: kind,
            usedPercent: Int(window.usedPercent.rounded()),
            resetsAt: window.resetsAt,
            durationMinutes: durationMinutes
        )
    }
}
