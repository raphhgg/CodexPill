import Foundation

/// Claude Code usage from its status line relay: the provider source for the menu, plus the
/// opt-in connect and disconnect steps that edit Claude Code's `settings.json`.
struct ClaudeCodeUsage: UsageProviderSource {
    let provider = UsageProvider.claude
    let staleAfter: TimeInterval = 3_600
    /// Reading two small local files is cheap, so every refresh reads them.
    let refreshInterval: TimeInterval = 0

    let installer: ClaudeStatusLineInstaller
    let reader: ClaudeUsageReader

    func readUsage(now: Date) async -> UsageProviderReading {
        guard installer.isInstalled else { return .notConnected }
        do {
            switch try reader.read(now: now) {
            case .notConnected, .awaitingUsage:
                return .awaitingUsage
            case let .current(snapshot), let .stale(snapshot):
                return .snapshot(Self.usage(from: snapshot))
            }
        } catch {
            return .unavailable(.readFailed)
        }
    }

    func connectionChange() throws(ClaudeStatusLineInstallError) -> ClaudeStatusLineChange? {
        try installer.previewInstall()
    }

    func disconnectionChange() throws(ClaudeStatusLineInstallError) -> ClaudeStatusLineChange? {
        try installer.previewUninstall()
    }

    func connect(confirming change: ClaudeStatusLineChange) throws(ClaudeStatusLineInstallError) {
        try installer.install(confirming: change)
    }

    /// Restores the previous status line and deletes the saved usage, so nothing stays behind.
    func disconnect(confirming change: ClaudeStatusLineChange) throws(ClaudeStatusLineInstallError) {
        try installer.uninstall(confirming: change)
        try? FileManager.default.removeItem(at: reader.fileURL)
    }

    static func usage(from snapshot: ClaudeUsageSnapshot) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            planName: nil,
            windows: snapshot.windows.map { window in
                UsageWindow(
                    kind: window.kind.usageWindowKind,
                    usedPercent: Int(window.usedPercent.rounded()),
                    resetsAt: window.resetsAt,
                    durationMinutes: window.kind.durationMinutes
                )
            },
            fetchedAt: snapshot.capturedAt
        )
    }
}

private extension ClaudeUsageWindowKind {
    var usageWindowKind: UsageWindowKind {
        switch self {
        case .fiveHour: .session
        case .sevenDay: .weekly
        }
    }
}
