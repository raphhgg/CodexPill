import Foundation

/// Claude Code subscription limits for the menu, and the Claude accounts CodexPill saved. The card reads Claude
/// Code's live sign-in once the user connects it; each saved account is read with its own saved sign-in.
struct ClaudeCodeUsage: ProviderConnection {
    let provider = UsageProvider.claude
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: ClaudeUsageSettingsStore
    let client: ClaudeUsageClient
    /// Saved Claude Code sign-ins to switch between. Nil when this build can't switch.
    let accounts: ClaudeCodeAccountStore?
    /// Claude Code's own login and renewal. Nil when this build can't add accounts.
    let commands: ClaudeCodeCommands?
    /// `CLAUDE_CONFIG_DIR` for Claude Code's live sign-in, or nil for its default folder.
    let liveConfigDirectory: String?
    private let liveRenewals = ClaudeLiveRenewalAttempts()

    init(
        settings: ClaudeUsageSettingsStore,
        client: ClaudeUsageClient,
        accounts: ClaudeCodeAccountStore? = nil,
        commands: ClaudeCodeCommands? = nil,
        liveConfigDirectory: String? = nil,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.accounts = accounts
        self.commands = commands
        self.liveConfigDirectory = liveConfigDirectory
        self.refreshInterval = refreshInterval
    }

    /// Turns the feature on and lets the next read ask for Keychain access, since the user just asked for it.
    func connect() async {
        settings.isEnabled = true
        await client.allowKeychainPromptOnNextRead()
    }

    var isConnected: Bool {
        settings.isEnabled
    }

    func disconnect() async {
        settings.isEnabled = false
    }

    var signInAvailability: ProviderSignInAvailability {
        guard accounts != nil, let commands else { return .unsupported }
        return commands.isInstalled ? .available : .notInstalled
    }

    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount] {
        guard let accounts else { return [] }
        do {
            let activeID = try accounts.activeAccountID()
            return try accounts.accounts().map {
                ProviderAccount(
                    id: $0.id,
                    email: $0.email,
                    name: $0.organizationName,
                    isActive: $0.id == activeID,
                    usage: $0.usage.flatMap(Self.snapshot(from:))
                )
            }
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

    /// Runs `claude auth login` in a throwaway config folder and saves the account it signed in to. When Claude Code
    /// has no sign-in at all, it signs Claude Code itself in instead, so the new account can be used right away.
    func addAccount() async throws(ProviderNotice) -> Bool {
        let store: ClaudeCodeAccountStore
        do {
            store = try self.store()
        } catch {
            throw error.notice
        }
        guard let commands else { throw ClaudeCodeAccountError.switchingUnavailable.notice }

        let signsInClaudeCode = if case .signedOut = store.claudeCode.current(allowingPrompt: false) { true } else { false }
        let signIn: ClaudeCodeSignInSnapshot?
        do {
            if signsInClaudeCode {
                try await commands.signInToClaudeCode(configDirectory: liveConfigDirectory)
                signIn = nil
            } else {
                signIn = try await commands.signIn()
            }
        } catch {
            if error == .cancelled { return false }
            throw error.notice
        }

        do {
            if let signIn {
                try store.add(signIn)
            } else {
                try store.captureCurrent()
            }
        } catch {
            throw error.notice
        }
        settings.isEnabled = true
        if signsInClaudeCode {
            await client.allowKeychainPromptOnNextRead()
        }
        return true
    }

    func saveLiveAccountIfNew() async -> Bool {
        guard settings.isEnabled, let accounts else { return false }
        return ((try? accounts.saveCurrentIfNew()) ?? nil) != nil
    }

    func removeAccount(_ id: UUID) async throws(ProviderNotice) {
        do {
            try store().delete(id)
        } catch {
            throw error.notice
        }
    }

    /// An expired saved sign-in is renewed by Claude Code in a throwaway folder first, and saved again only if the
    /// saved copy did not change meanwhile. When it can't be renewed, the account keeps its last limits.
    func refreshInactiveAccount(_ id: UUID, now: Date) async {
        guard let accounts, (try? accounts.activeAccountID()) != id, var signIn = try? accounts.savedSignIn(id) else { return }
        let isExpired = ((try? ClaudeCredentials(json: signIn.itemData)) ?? nil)?.isExpired(at: now) ?? true
        if isExpired {
            guard
                let renewed = try? await commands?.renew(signIn),
                accounts.replaceSavedSignIn(id, with: renewed, ifUnchangedFrom: signIn)
            else {
                return
            }
            signIn = renewed
        }
        guard case let .available(report, planName) = await client.refresh(savedSignIn: signIn, now: now) else { return }
        try? accounts.recordUsage(ClaudeCodeSavedUsage(report: report, planName: planName, fetchedAt: now), for: id)
    }

    /// Runs `claude doctor` with Claude Code's own config once its live token has expired, so Claude Code renews its
    /// own sign-in. Never early, never while a `claude` process runs, since that one renews the token itself.
    func renewLiveSignInIfNeeded(now: Date) async -> Bool {
        guard
            settings.isEnabled,
            let commands, commands.isInstalled,
            let processes = accounts?.processes,
            let expiry = await client.liveSignInExpiry(), expiry <= now,
            !processes.isClaudeCodeRunning(),
            await liveRenewals.claim(expiry: expiry, now: now)
        else {
            return false
        }
        try? await commands.renewClaudeCode(configDirectory: liveConfigDirectory)
        guard let renewedExpiry = await client.liveSignInExpiry() else { return false }
        return renewedExpiry != expiry
    }

    private func store() throws(ClaudeCodeAccountError) -> ClaudeCodeAccountStore {
        guard let accounts else { throw .switchingUnavailable }
        return accounts
    }

    private static func snapshot(from usage: ClaudeCodeSavedUsage) -> UsageSnapshot? {
        guard case let .snapshot(snapshot) = reading(from: .available(usage.report, planName: usage.planName), fetchedAt: usage.fetchedAt) else {
            return nil
        }
        return snapshot
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
            let mainWindows = [
                report.fiveHour.map { usageWindow(.session, $0.usedPercent, $0.resetsAt, durationMinutes: 300) },
                report.sevenDay.map { usageWindow(.weekly, $0.usedPercent, $0.resetsAt, durationMinutes: 10_080) },
            ].compactMap(\.self)
            guard !mainWindows.isEmpty else { return .awaitingUsage }
            let windows = mainWindows + report.modelWeeks.map {
                usageWindow(.modelWeekly(modelName: $0.modelName), $0.usedPercent, $0.resetsAt, durationMinutes: 10_080)
            }
            return .snapshot(UsageSnapshot(provider: .claude, planName: planName, windows: windows, fetchedAt: fetchedAt))
        }
    }

    private static func usageWindow(_ kind: UsageWindowKind, _ usedPercent: Double, _ resetsAt: Date?, durationMinutes: Int) -> UsageWindow {
        UsageWindow(kind: kind, usedPercent: Int(usedPercent.rounded()), resetsAt: resetsAt, durationMinutes: durationMinutes)
    }
}

/// One renewal per expiry, and another for the same expiry only after `retryAfter`, so a sign-in Claude Code can't
/// renew does not run `claude doctor` on every read.
actor ClaudeLiveRenewalAttempts {
    static let retryAfter: TimeInterval = 30 * 60

    private var lastExpiry: Date?
    private var lastAttemptAt: Date?

    func claim(expiry: Date, now: Date) -> Bool {
        if expiry == lastExpiry, let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < Self.retryAfter {
            return false
        }
        lastExpiry = expiry
        lastAttemptAt = now
        return true
    }
}
