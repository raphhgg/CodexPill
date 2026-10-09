import Foundation

@testable import CodexPill

/// A temp folder standing in for `~/.claude` and CodexPill's app-support folder.
struct ClaudeCodeFixture {
    let root: URL
    let usage: ClaudeCodeUsage

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCodeFixture-\(UUID().uuidString)", isDirectory: true)
        let relaySource = root.appendingPathComponent("bundle/codexpill-claude-usage-relay.sh")
        try FileManager.default.createDirectory(at: relaySource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: relaySource)
        usage = ClaudeCodeUsage(
            installer: ClaudeStatusLineInstaller(
                relaySourceURL: relaySource,
                claudeConfigDirectory: root.appendingPathComponent("home/.claude", isDirectory: true),
                relayInstallURL: root.appendingPathComponent("support/bin/codexpill-claude-usage-relay.sh")
            ),
            reader: ClaudeUsageReader(fileURL: root.appendingPathComponent("support/claude-usage.json"))
        )
    }

    var settingsURL: URL { usage.installer.settingsURL }
    var relayPath: String { usage.installer.relayInstallURL.path }

    func writeSettings(_ json: String) throws {
        try FileManager.default.createDirectory(at: usage.installer.claudeConfigDirectory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: settingsURL)
    }

    func writeRelayOutput(_ json: String) throws {
        try FileManager.default.createDirectory(
            at: usage.reader.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: usage.reader.fileURL)
    }

    func settingsObject() throws -> NSDictionary? {
        try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? NSDictionary
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
