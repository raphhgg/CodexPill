import Foundation

/// Claude subscription limits for the menu, read only after the user connects Claude. CodexPill's own
/// "Sign in with Claude" comes first; Claude Code's unexpired sign-in is the fallback for terminal users.
struct ClaudeCodeUsage: UsageProviderSource {
    let provider = UsageProvider.claude
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: ClaudeUsageSettingsStore
    let client: ClaudeUsageClient
    /// Saved Claude Code sign-ins to switch between. Nil in isolated runs, which never write the real Keychain.
    let accounts: ClaudeCodeAccountStore?
    let signInFlow: any ClaudeSignInAuthorizing

    init(
        settings: ClaudeUsageSettingsStore,
        client: ClaudeUsageClient,
        signInFlow: any ClaudeSignInAuthorizing,
        accounts: ClaudeCodeAccountStore? = nil,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.accounts = accounts
        self.signInFlow = signInFlow
        self.refreshInterval = refreshInterval
    }

    /// Connects with Claude Code's sign-in when it is readable without a prompt and unexpired. Returns false when
    /// the user has to sign in with Claude in the browser instead.
    func connectWithClaudeCodeSignIn(now: Date) async -> Bool {
        guard await client.hasUsableClaudeCodeSignIn(now: now) else { return false }
        settings.isEnabled = true
        return true
    }

    /// Runs "Sign in with Claude" in the browser. Claude stays connected only if the sign-in succeeds, so a cancelled
    /// or timed-out first sign-in leaves Claude not connected.
    @discardableResult
    func signIn() async -> Bool {
        guard let signIn = try? await signInFlow.signIn() else { return false }
        await client.store(signIn)
        settings.isEnabled = true
        return true
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

    /// Forgets the opt-in and deletes CodexPill's own sign-in. Claude Code's sign-in is untouched.
    func disconnect() async {
        settings.isEnabled = false
        await client.forgetSignIn()
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
