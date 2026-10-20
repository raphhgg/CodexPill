import Foundation

/// Claude subscription limits for the menu, read once the user connects Claude: with Claude Code's live sign-in, or
/// with rusage's own "Sign in with Claude" once the user signs in. rusage's own sign-in never falls back to Claude
/// Code's, which may be another account.
struct ClaudeCodeUsage: ProviderConnection {
    let provider = UsageProvider.claude
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: ClaudeUsageSettingsStore
    let client: ClaudeUsageClient
    private let browserSignIn: ClaudeBrowserSignInSession

    init(
        settings: ClaudeUsageSettingsStore,
        client: ClaudeUsageClient,
        signInFlow: any ClaudeSignInAuthorizing,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.refreshInterval = refreshInterval
        browserSignIn = ClaudeBrowserSignInSession(flow: signInFlow, client: client, settings: settings)
    }

    /// Turns the feature on and lets the next read ask for Keychain access, since the user just asked for it.
    func connect() async {
        settings.isEnabled = true
        await client.allowKeychainPromptOnNextRead()
    }

    var isConnected: Bool {
        settings.isEnabled
    }

    /// Also signs out of rusage's own sign-in. Claude Code's sign-in is untouched.
    func disconnect() async {
        await browserSignIn.cancel()
        settings.isEnabled = false
        settings.usesOwnSignIn = false
        _ = await client.signOut()
    }

    var ownSignIn: ProviderOwnSignIn {
        settings.usesOwnSignIn ? .signedIn : .signedOut
    }

    func signIn() async throws(ProviderNotice) {
        try await browserSignIn.run()
    }

    /// Reads go back to Claude Code's sign-in.
    func signOut() async throws(ProviderNotice) {
        await browserSignIn.cancel()
        settings.usesOwnSignIn = false
        guard await client.signOut() else {
            throw ProviderNotice(title: "Claude sign-in not removed", detail: "Remove it in Keychain Access.")
        }
    }

    func readUsage(now: Date) async -> UsageProviderReading {
        guard settings.isEnabled else { return .notConnected }
        return Self.reading(from: await client.refresh(now: now, using: settings.usesOwnSignIn ? .rusage : .claudeCode), fetchedAt: now)
    }

    static func reading(from status: ClaudeUsageStatus, fetchedAt: Date) -> UsageProviderReading {
        switch status {
        case .signedOut: return .unavailable(.signedOut)
        case .keychainAccessNeeded: return .unavailable(.keychainAccessNeeded)
        case .signInUnreadable: return .unavailable(.signInUnreadable)
        case .signInExpired: return .unavailable(.signInExpired)
        case .signInRequired: return .unavailable(.signInRequired)
        case .forbidden: return .unavailable(.accessDenied)
        case .rateLimited: return .unavailable(.rateLimited)
        case .unreachable: return .unavailable(.unreachable)
        case .serviceError: return .unavailable(.serviceError)
        case .unexpectedResponse: return .unavailable(.unexpectedResponse)
        case let .available(report, planName, email):
            let mainWindows = [
                report.fiveHour.map { usageWindow(.session, $0.usedPercent, $0.resetsAt, durationMinutes: 300) },
                report.sevenDay.map { usageWindow(.weekly, $0.usedPercent, $0.resetsAt, durationMinutes: 10_080) },
            ].compactMap(\.self)
            guard !mainWindows.isEmpty else { return .awaitingUsage }
            let windows = mainWindows + report.modelWeeks.map {
                usageWindow(.modelWeekly(modelName: $0.modelName), $0.usedPercent, $0.resetsAt, durationMinutes: 10_080)
            }
            return .snapshot(UsageSnapshot(
                provider: .claude,
                planName: planName,
                windows: windows,
                fetchedAt: fetchedAt,
                credits: report.extraUsage.map { .extraUsage(spent: $0.spent, limit: $0.limit, currencyCode: $0.currencyCode) },
                accountEmail: email
            ))
        }
    }

    private static func usageWindow(_ kind: UsageWindowKind, _ usedPercent: Double, _ resetsAt: Date?, durationMinutes: Int) -> UsageWindow {
        UsageWindow(kind: kind, usedPercent: Int(usedPercent.rounded()), resetsAt: resetsAt, durationMinutes: durationMinutes)
    }
}

/// "Sign in with Claude…" from the menu, one browser sign-in at a time. Starting another cancels the running one,
/// because the user may have closed its tab.
actor ClaudeBrowserSignInSession {
    private let flow: any ClaudeSignInAuthorizing
    private let client: ClaudeUsageClient
    private let settings: ClaudeUsageSettingsStore
    private var running: Task<ClaudeSignIn, any Error>?

    init(flow: any ClaudeSignInAuthorizing, client: ClaudeUsageClient, settings: ClaudeUsageSettingsStore) {
        self.flow = flow
        self.client = client
        self.settings = settings
    }

    /// Settings change only once the sign-in succeeds, so a cancelled sign-in leaves everything as it was.
    func run() async throws(ProviderNotice) {
        running?.cancel()
        let task = Task { [flow] in try await flow.signIn() }
        running = task
        defer {
            if running == task { running = nil }
        }
        let signIn: ClaudeSignIn
        do {
            signIn = try await task.value
        } catch let error as ClaudeSignInError where !task.isCancelled {
            throw error.notice
        } catch {
            return
        }
        guard !task.isCancelled else { return }
        let saved = await client.store(signIn)
        guard !task.isCancelled else { return }
        settings.isEnabled = true
        settings.usesOwnSignIn = true
        guard saved else {
            throw ProviderNotice(title: "Claude sign-in not saved", detail: "It lasts until rusage quits.")
        }
    }

    func cancel() {
        running?.cancel()
    }
}
