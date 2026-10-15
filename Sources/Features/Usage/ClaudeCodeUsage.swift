import Foundation

/// Claude Code subscription limits for the menu, read from Claude Code's live sign-in once the user connects it.
struct ClaudeCodeUsage: ProviderConnection {
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
