import Foundation

/// Claude Code subscription limits for the menu, read from Claude Code's live sign-in once the user connects it.
struct ClaudeCodeUsage: ProviderConnection {
    let provider = UsageProvider.claude
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: ClaudeUsageSettingsStore
    let client: ClaudeUsageClient
    /// Runs `claude doctor` so Claude Code renews its own sign-in. Nil when this build never runs `claude`.
    let commands: ClaudeCodeCommands?
    /// Tells whether a terminal `claude` runs, which renews the sign-in itself.
    let processes: (any ClaudeCodeProcessDetecting)?
    /// `CLAUDE_CONFIG_DIR` for Claude Code's live sign-in, or nil for its default folder.
    let liveConfigDirectory: String?
    private let liveRenewals = ClaudeLiveRenewalAttempts()

    init(
        settings: ClaudeUsageSettingsStore,
        client: ClaudeUsageClient,
        commands: ClaudeCodeCommands? = nil,
        processes: (any ClaudeCodeProcessDetecting)? = nil,
        liveConfigDirectory: String? = nil,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.commands = commands
        self.processes = processes
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

    /// Runs `claude doctor` with Claude Code's own config once its live token has expired, so Claude Code renews its
    /// own sign-in. Never early, never while a `claude` process runs, since that one renews the token itself.
    func renewLiveSignInIfNeeded(now: Date) async -> Bool {
        guard
            settings.isEnabled,
            let commands, commands.isInstalled,
            let processes,
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
