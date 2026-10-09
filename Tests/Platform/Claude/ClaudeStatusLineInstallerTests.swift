import Foundation
import Testing

@testable import CodexPill

struct ClaudeStatusLineInstallerTests {
    private let originalSettings = """
    {
      "env": {"ANTHROPIC_LOG": "error"},
      "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}
    }

    """

    @Test
    func installThenUninstallRestoresSettingsAndRemovesRelayCopy() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try makeInstaller(root: root)
        try FileManager.default.createDirectory(at: installer.claudeConfigDirectory, withIntermediateDirectories: true)
        try Data(originalSettings.utf8).write(to: installer.settingsURL)
        try setPosixPermissions(0o644, at: installer.settingsURL)

        let installPlan = try installer.install()

        guard case let .write(_, previousCommand) = installPlan else {
            Issue.record("Expected a settings write, got \(installPlan)")
            return
        }
        #expect(previousCommand == "~/.claude/statusline.sh")
        #expect(try statusLineCommand(at: installer.settingsURL) == "'\(installer.relayInstallURL.path)' '~/.claude/statusline.sh'")
        #expect(try Data(contentsOf: installer.relayInstallURL) == Data("#!/bin/sh\necho relay\n".utf8))
        #expect(try posixPermissions(at: installer.relayInstallURL) == 0o700)
        #expect(try posixPermissions(at: installer.relayInstallURL.deletingLastPathComponent()) == 0o700)
        #expect(try posixPermissions(at: installer.settingsURL) == 0o644)
        #expect(try installer.install() == .unchanged(.alreadyInstalled))

        try installer.uninstall()

        #expect(try object(at: installer.settingsURL) == object(Data(originalSettings.utf8)))
        #expect(!FileManager.default.fileExists(atPath: installer.relayInstallURL.path))
    }

    @Test
    func installWithoutSettingsFileCreatesPrivateSettingsAndNoBackup() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try makeInstaller(root: root)

        try installer.install()

        #expect(try statusLineCommand(at: installer.settingsURL) == "'\(installer.relayInstallURL.path)'")
        #expect(try posixPermissions(at: installer.settingsURL) == 0o600)
        #expect(!FileManager.default.fileExists(atPath: installer.backupURL.path))
    }

    @Test
    func symlinkedSettingsAreWrittenThroughTheLink() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try makeInstaller(root: root)
        let dotfiles = root.appendingPathComponent("dotfiles", isDirectory: true)
        let target = dotfiles.appendingPathComponent("claude-settings.json")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installer.claudeConfigDirectory, withIntermediateDirectories: true)
        try Data(originalSettings.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: installer.settingsURL, withDestinationURL: target)

        try installer.install()

        let attributes = try FileManager.default.attributesOfItem(atPath: installer.settingsURL.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try statusLineCommand(at: target) == "'\(installer.relayInstallURL.path)' '~/.claude/statusline.sh'")
    }

    @Test
    func backupKeepsTheFirstOriginalAcrossReinstalls() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try makeInstaller(root: root)
        try FileManager.default.createDirectory(at: installer.claudeConfigDirectory, withIntermediateDirectories: true)
        try Data(originalSettings.utf8).write(to: installer.settingsURL)

        try installer.install()
        try installer.uninstall()
        try Data(#"{"model":"haiku"}"#.utf8).write(to: installer.settingsURL)
        try installer.install()

        #expect(try Data(contentsOf: installer.backupURL) == Data(originalSettings.utf8))
        #expect(try posixPermissions(at: installer.backupURL) == 0o600)
    }

    @Test
    func invalidSettingsAreLeftUntouched() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try makeInstaller(root: root)
        try FileManager.default.createDirectory(at: installer.claudeConfigDirectory, withIntermediateDirectories: true)
        let invalid = Data(#"{"statusLine": "oops""#.utf8)
        try invalid.write(to: installer.settingsURL)

        #expect(throws: ClaudeStatusLineInstallError.invalidSettings(.settingsNotJSON)) {
            try installer.install()
        }
        #expect(try Data(contentsOf: installer.settingsURL) == invalid)
        #expect(!FileManager.default.fileExists(atPath: installer.backupURL.path))
    }

    @Test
    func configDirectoryHonorsClaudeConfigDirEnvironment() {
        let url = ClaudeStatusLineInstaller.defaultClaudeConfigDirectory(environment: ["CLAUDE_CONFIG_DIR": "/tmp/alt-claude"])

        #expect(url.path == "/tmp/alt-claude")
    }

    private func makeInstaller(root: URL) throws -> ClaudeStatusLineInstaller {
        let source = root.appendingPathComponent("bundle/codexpill-claude-usage-relay.sh")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho relay\n".utf8).write(to: source)
        return ClaudeStatusLineInstaller(
            relaySourceURL: source,
            claudeConfigDirectory: root.appendingPathComponent("home/.claude", isDirectory: true),
            relayInstallURL: root.appendingPathComponent("Application Support/CodexPill/bin/codexpill-claude-usage-relay.sh")
        )
    }

    private func statusLineCommand(at url: URL) throws -> String? {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return (root?["statusLine"] as? [String: Any])?["command"] as? String
    }

    private func object(at url: URL) throws -> NSDictionary {
        try object(Data(contentsOf: url))
    }

    private func object(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeStatusLineInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    private func setPosixPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}
