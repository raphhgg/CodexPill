import Foundation

/// Claude Code subscription limits for the menu, read from Claude Code's sign-in only after the user connects it.
struct ClaudeCodeUsage: UsageProviderSource {
    let provider = UsageProvider.claude
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: ClaudeUsageSettingsStore
    let client: ClaudeUsageClient

    init(
        settings: ClaudeUsageSettingsStore,
        client: ClaudeUsageClient,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
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
        case .signInExpired: return .unavailable(.signInExpired)
        case .unavailable: return .unavailable(.readFailed)
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
