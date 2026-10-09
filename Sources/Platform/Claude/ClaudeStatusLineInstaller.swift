import Foundation

enum ClaudeStatusLineInstallError: Error, Equatable, Sendable {
    case relayCopyFailed
    case settingsUnreadable
    case invalidSettings(ClaudeStatusLinePlanError)
    case backupFailed
    case settingsWriteFailed
    /// `settings.json` changed between the consent preview and the write.
    case settingsChanged
}

/// The `statusLine` entry before and after a planned write, as pretty JSON, for the consent view.
/// Only this entry is shown because the rest of `settings.json` can hold secrets.
struct ClaudeStatusLineChange: Equatable, Sendable {
    let settingsPath: String
    let before: String?
    let after: String?
}

/// Applies `ClaudeStatusLineInstallPlanner` plans to Claude Code's real
/// `settings.json` and keeps the relay script at a stable app-support path, so
/// the user's status line survives CodexPill being moved or deleted.
struct ClaudeStatusLineInstaller: Sendable {
    static let backupSuffix = ".codexpill-backup"

    let relaySourceURL: URL
    let claudeConfigDirectory: URL
    let relayInstallURL: URL
    private var fileManager: FileManager { .default }

    init(
        relaySourceURL: URL,
        claudeConfigDirectory: URL = Self.defaultClaudeConfigDirectory(),
        relayInstallURL: URL = Self.defaultRelayInstallURL()
    ) {
        self.relaySourceURL = relaySourceURL
        self.claudeConfigDirectory = claudeConfigDirectory
        self.relayInstallURL = relayInstallURL
    }

    static func defaultClaudeConfigDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    static func defaultRelayInstallURL(fileManager: FileManager = .default) -> URL {
        ClaudeUsageReader.defaultFileURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(ClaudeStatusLineInstallPlanner.relayFileName)
    }

    var settingsURL: URL {
        claudeConfigDirectory.appendingPathComponent("settings.json")
    }

    var backupURL: URL {
        claudeConfigDirectory.appendingPathComponent("settings.json" + Self.backupSuffix)
    }

    /// True when `settings.json` runs a CodexPill relay. Unreadable or invalid settings count as not installed.
    var isInstalled: Bool {
        (try? previewUninstall()) != nil
    }

    @discardableResult
    func install() throws(ClaudeStatusLineInstallError) -> ClaudeStatusLinePlan {
        let existing = try readSettings()
        let plan = try planInstall(over: existing)
        try copyRelay()
        try apply(plan, over: existing)
        return plan
    }

    @discardableResult
    func uninstall() throws(ClaudeStatusLineInstallError) -> ClaudeStatusLinePlan {
        let existing = try readSettings()
        let plan = try planUninstall(over: existing)
        try applyUninstall(plan, over: existing)
        return plan
    }

    /// The change `install(confirming:)` would make, or nil when the relay is already installed.
    func previewInstall() throws(ClaudeStatusLineInstallError) -> ClaudeStatusLineChange? {
        let existing = try readSettings()
        return change(for: try planInstall(over: existing), over: existing)
    }

    /// The change `uninstall(confirming:)` would make, or nil when no relay is installed.
    func previewUninstall() throws(ClaudeStatusLineInstallError) -> ClaudeStatusLineChange? {
        let existing = try readSettings()
        return change(for: try planUninstall(over: existing), over: existing)
    }

    /// Installs only if the planned change still matches the one the user agreed to.
    func install(confirming expected: ClaudeStatusLineChange) throws(ClaudeStatusLineInstallError) {
        let existing = try readSettings()
        let plan = try planInstall(over: existing)
        guard change(for: plan, over: existing) == expected else { throw .settingsChanged }
        try copyRelay()
        try apply(plan, over: existing)
    }

    /// Uninstalls only if the planned change still matches the one the user agreed to.
    func uninstall(confirming expected: ClaudeStatusLineChange) throws(ClaudeStatusLineInstallError) {
        let existing = try readSettings()
        let plan = try planUninstall(over: existing)
        guard change(for: plan, over: existing) == expected else { throw .settingsChanged }
        try applyUninstall(plan, over: existing)
    }

    private func planInstall(over existing: ExistingSettings?) throws(ClaudeStatusLineInstallError) -> ClaudeStatusLinePlan {
        do {
            return try ClaudeStatusLineInstallPlanner.planInstall(
                settings: existing?.data,
                relayPath: relayInstallURL.path
            )
        } catch {
            throw .invalidSettings(error)
        }
    }

    private func planUninstall(over existing: ExistingSettings?) throws(ClaudeStatusLineInstallError) -> ClaudeStatusLinePlan {
        do {
            return try ClaudeStatusLineInstallPlanner.planUninstall(settings: existing?.data)
        } catch {
            throw .invalidSettings(error)
        }
    }

    private func applyUninstall(
        _ plan: ClaudeStatusLinePlan,
        over existing: ExistingSettings?
    ) throws(ClaudeStatusLineInstallError) {
        try apply(plan, over: existing)
        if case .write = plan {
            try? fileManager.removeItem(at: relayInstallURL)
        }
    }

    private func change(for plan: ClaudeStatusLinePlan, over existing: ExistingSettings?) -> ClaudeStatusLineChange? {
        guard case let .write(settings, _) = plan else { return nil }
        return ClaudeStatusLineChange(
            settingsPath: settingsURL.path,
            before: ClaudeStatusLineInstallPlanner.statusLineJSON(in: existing?.data),
            after: ClaudeStatusLineInstallPlanner.statusLineJSON(in: settings)
        )
    }

    private struct ExistingSettings {
        /// The symlink-resolved file, so dotfiles-managed links are written through.
        let resolvedURL: URL
        let data: Data
        let permissions: Int?
    }

    private func copyRelay() throws(ClaudeStatusLineInstallError) {
        do {
            let relay = try Data(contentsOf: relaySourceURL)
            try FilePermissionHardening.createPrivateDirectory(
                at: relayInstallURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
            try relay.write(to: relayInstallURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: FilePermissionHardening.privateDirectoryPermissions],
                ofItemAtPath: relayInstallURL.path
            )
        } catch {
            throw .relayCopyFailed
        }
    }

    private func readSettings() throws(ClaudeStatusLineInstallError) -> ExistingSettings? {
        let resolvedURL = settingsURL.resolvingSymlinksInPath()
        do {
            let data = try Data(contentsOf: resolvedURL)
            let permissions = (try? fileManager.attributesOfItem(atPath: resolvedURL.path))?[.posixPermissions] as? Int
            return ExistingSettings(resolvedURL: resolvedURL, data: data, permissions: permissions)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw .settingsUnreadable
        }
    }

    private func apply(
        _ plan: ClaudeStatusLinePlan,
        over existing: ExistingSettings?
    ) throws(ClaudeStatusLineInstallError) {
        guard case let .write(settings, _) = plan else { return }

        if let existing, !fileManager.fileExists(atPath: backupURL.path) {
            do {
                try existing.data.write(to: backupURL, options: .atomic)
                // settings.json can hold env secrets, so the copy stays owner-only.
                try FilePermissionHardening.repairPrivateFile(at: backupURL, fileManager: fileManager)
            } catch {
                throw .backupFailed
            }
        }

        let targetURL = existing?.resolvedURL ?? settingsURL
        do {
            if existing == nil {
                try fileManager.createDirectory(
                    at: claudeConfigDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: FilePermissionHardening.privateDirectoryPermissions]
                )
            }
            try settings.write(to: targetURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: existing?.permissions ?? FilePermissionHardening.privateFilePermissions],
                ofItemAtPath: targetURL.path
            )
        } catch {
            throw .settingsWriteFailed
        }
    }
}
