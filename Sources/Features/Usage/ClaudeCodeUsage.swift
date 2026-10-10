import Foundation

/// Claude subscription limits for the menu, read only after the user connects Claude, with the one sign-in they
/// connected: Claude Code's, or CodexPill's own "Sign in with Claude".
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
        settings.connection = .claudeCode
        return true
    }

    /// Runs "Sign in with Claude" in the browser. The connection changes only if the sign-in succeeds, so a cancelled
    /// first sign-in leaves Claude not connected and a cancelled sign-in again keeps asking for one.
    func signIn() async throws(ClaudeSignInError) {
        let signIn: ClaudeSignIn
        do {
            signIn = try await signInFlow.signIn()
        } catch let error as ClaudeSignInError {
            throw error
        } catch {
            // Only cancellation gets here: the user cancelled the sign-in or disconnected.
            return
        }
        await client.store(signIn)
        settings.connection = .codexPill
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
    /// Returns false when CodexPill's own sign-in is still in the Keychain.
    @discardableResult
    func disconnect() async -> Bool {
        settings.connection = nil
        return await client.forgetSignIn()
    }

    func readUsage(now: Date) async -> UsageProviderReading {
        guard let source = settings.connection else { return .notConnected }
        return Self.reading(from: await client.refresh(now: now, using: source), source: source, fetchedAt: now)
    }

    static func reading(from status: ClaudeUsageStatus, source: ClaudeSignInSource, fetchedAt: Date) -> UsageProviderReading {
        switch status {
        case .signedOut: return .unavailable(.signedOut)
        case .keychainAccessNeeded: return .unavailable(.keychainAccessNeeded)
        case .signInUnreadable: return .unavailable(.signInUnreadable)
        case .signInExpired: return .unavailable(source == .codexPill ? .signInRequired : .signInExpired)
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
