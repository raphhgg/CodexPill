import Foundation

enum ClaudeStatusLineInstallError: Error, Equatable, Sendable {
    case relayCopyFailed
    case settingsUnreadable
    case invalidSettings(ClaudeStatusLinePlanError)
    case backupFailed
    case settingsWriteFailed
}

/// Applies `ClaudeStatusLineInstallPlanner` plans to Claude Code's real
/// `settings.json` and keeps the relay script at a stable app-support path, so
/// the user's status line survives CodexPill being moved or deleted.
struct ClaudeStatusLineInstaller {
    static let backupSuffix = ".codexpill-backup"

    let relaySourceURL: URL
    let claudeConfigDirectory: URL
    let relayInstallURL: URL
    private let fileManager: FileManager

    init(
        relaySourceURL: URL,
        claudeConfigDirectory: URL = Self.defaultClaudeConfigDirectory(),
        relayInstallURL: URL = Self.defaultRelayInstallURL(),
        fileManager: FileManager = .default
    ) {
        self.relaySourceURL = relaySourceURL
        self.claudeConfigDirectory = claudeConfigDirectory
        self.relayInstallURL = relayInstallURL
        self.fileManager = fileManager
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

    @discardableResult
    func install() throws(ClaudeStatusLineInstallError) -> ClaudeStatusLinePlan {
        let existing = try readSettings()
        let plan: ClaudeStatusLinePlan
        do {
            plan = try ClaudeStatusLineInstallPlanner.planInstall(
                settings: existing?.data,
                relayPath: relayInstallURL.path
            )
        } catch {
            throw .invalidSettings(error)
        }
        try copyRelay()
        try apply(plan, over: existing)
        return plan
    }

    @discardableResult
    func uninstall() throws(ClaudeStatusLineInstallError) -> ClaudeStatusLinePlan {
        let existing = try readSettings()
        let plan: ClaudeStatusLinePlan
        do {
            plan = try ClaudeStatusLineInstallPlanner.planUninstall(settings: existing?.data)
        } catch {
            throw .invalidSettings(error)
        }
        try apply(plan, over: existing)
        if case .write = plan {
            try? fileManager.removeItem(at: relayInstallURL)
        }
        return plan
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
