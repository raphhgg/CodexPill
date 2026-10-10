import Foundation

/// Claude subscription limits for the menu, read only after the user connects Claude. CodexPill's own
/// "Sign in with Claude" comes first; Claude Code's unexpired sign-in is the fallback for terminal users.
struct ClaudeCodeUsage: ProviderConnection {
    let provider = UsageProvider.claude
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: ClaudeUsageSettingsStore
    let client: ClaudeUsageClient
    /// Saved Claude Code sign-ins to switch between. Nil in isolated runs, which never write the real Keychain.
    let accounts: ClaudeCodeAccountStore?
    private let browserSignIn: ClaudeUsageSignIn

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
        self.refreshInterval = refreshInterval
        browserSignIn = ClaudeUsageSignIn(flow: signInFlow, client: client, settings: settings)
    }

    var signIn: (any ProviderSignIn)? { browserSignIn }

    /// Connects with Claude Code's sign-in when it is readable without a prompt and unexpired. Returns false when
    /// the user has to sign in with Claude in the browser instead. Once connected, it only lets the next read ask for
    /// Keychain access, since the user just asked for it.
    func connect() async -> Bool {
        guard settings.isEnabled else {
            guard await client.hasUsableClaudeCodeSignIn(now: Date()) else { return false }
            settings.isEnabled = true
            return true
        }
        await client.allowKeychainPromptOnNextRead()
        return true
    }

    /// Forgets the opt-in and deletes CodexPill's own sign-in. Claude Code's sign-in is untouched.
    func disconnect() async {
        await browserSignIn.cancel()
        settings.isEnabled = false
        await client.forgetSignIn()
    }

    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount] {
        guard let accounts else { return [] }
        do {
            let activeID = try accounts.activeAccountID()
            return try accounts.accounts().map { ProviderAccount(id: $0.id, email: $0.email, isActive: $0.id == activeID) }
        } catch {
            throw error.notice
        }
    }

    /// Signs Claude Code in to a saved account. The switch rewrote Claude Code's sign-in, which can reset its Keychain
    /// access rule, so the next read may show the Keychain prompt: the user just asked for this.
    func switchAccount(to id: UUID) async throws(ProviderNotice) {
        do {
            try store().activate(id)
        } catch {
            throw error.notice
        }
        await client.allowKeychainPromptOnNextRead()
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
            try store().delete(id)
        } catch {
            throw error.notice
        }
    }

    private func store() throws(ClaudeCodeAccountError) -> ClaudeCodeAccountStore {
        guard let accounts else { throw .switchingUnavailable }
        return accounts
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

/// "Sign in with Claude" from the menu: one browser sign-in at a time, which the menu can cancel.
actor ClaudeUsageSignIn: ProviderSignIn {
    private let flow: any ClaudeSignInAuthorizing
    private let client: ClaudeUsageClient
    private let settings: ClaudeUsageSettingsStore
    private var running: Task<ClaudeSignIn, any Error>?

    init(flow: any ClaudeSignInAuthorizing, client: ClaudeUsageClient, settings: ClaudeUsageSettingsStore) {
        self.flow = flow
        self.client = client
        self.settings = settings
    }

    /// Claude stays connected only if the sign-in succeeds, so a cancelled or timed-out first sign-in leaves Claude
    /// not connected.
    func run() async throws(ProviderNotice) -> Bool {
        let task = Task { [flow] in try await flow.signIn() }
        running = task
        defer { running = nil }
        guard let signIn = try? await task.value, !task.isCancelled else { return false }
        await client.store(signIn)
        settings.isEnabled = true
        return true
    }

    func cancel() {
        running?.cancel()
    }
}
