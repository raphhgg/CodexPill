import Foundation
import Testing

@testable import RUsage

struct CodexPillMigrationTests {
    @Test
    func copiesCodexPillFolderWithoutSavedClaudeAccountsWhenRUsageHasNone() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()

        #expect(fixture.migration().run() == .copied)

        #expect(try fixture.rusage("accounts.json") == #"[{"id":"saved"}]"#)
        #expect(try fixture.rusage("snapshots/saved.json") == "snapshot")
        #expect(try fixture.rusage("bin/tool") == "#!/bin/sh")
        #expect(try fixture.listing(of: fixture.rusageFolder).keys.sorted() == ["accounts.json", "bin", "bin/tool", "snapshots", "snapshots/saved.json"])
    }

    @Test
    func replacesAnEmptyRUsageCatalogWithCodexPillData() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        try fixture.writeRUsage("accounts.json", "[]\n")
        try FileManager.default.createDirectory(at: fixture.rusageFolder.appendingPathComponent("snapshots"), withIntermediateDirectories: true)

        #expect(fixture.migration().run() == .copied)

        #expect(try fixture.rusage("accounts.json") == #"[{"id":"saved"}]"#)
        #expect(try fixture.rusage("snapshots/saved.json") == "snapshot")
    }

    @Test(arguments: [
        ("accounts.json", #"[{"id":"rusage"}]"#),
        ("snapshots/rusage.json", "rusage snapshot"),
    ])
    func leavesRealRUsageDataUntouched(path: String, contents: String) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        try fixture.writeRUsage(path, contents)

        #expect(fixture.migration().run() == .keptRUsageData)

        #expect(try fixture.rusage(path) == contents)
        #expect(!FileManager.default.fileExists(atPath: fixture.rusageFolder.appendingPathComponent("bin").path))
    }

    @Test
    func savedClaudeAccountsATestBuildLeftInRUsageDoNotCountAsRUsageData() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        try fixture.writeRUsage("claude-code-accounts.json", "rusage claude")

        #expect(fixture.migration().run() == .copied)

        #expect(try fixture.rusage("accounts.json") == #"[{"id":"saved"}]"#)
    }

    @Test
    func removesSavedClaudeAccountsAnEarlierBuildCopiedToRUsage() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        #expect(fixture.migration().run() == .copied)
        try fixture.writeRUsage("claude-code-accounts.json", "copied claude")
        try fixture.writeRUsage("claude-sign-in/scratch", "scratch")

        #expect(fixture.migration().run() == .alreadyRan)

        #expect(try fixture.listing(of: fixture.rusageFolder).keys.sorted() == ["accounts.json", "bin", "bin/tool", "snapshots", "snapshots/saved.json"])
        #expect(FileManager.default.fileExists(atPath: fixture.codexPillFolder.appendingPathComponent("claude-code-accounts.json").path))
    }

    @Test
    func secondRunChangesNothing() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        #expect(fixture.migration().run() == .copied)
        try fixture.writeRUsage("accounts.json", "[]")
        try FileManager.default.removeItem(at: fixture.rusageFolder.appendingPathComponent("snapshots"))

        #expect(fixture.migration().run() == .alreadyRan)

        #expect(try fixture.rusage("accounts.json") == "[]")
    }

    @Test
    func leavesCodexPillFolderAsItWas() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        let before = try fixture.listing(of: fixture.codexPillFolder)

        _ = fixture.migration().run()

        #expect(try fixture.listing(of: fixture.codexPillFolder) == before)
    }

    @Test
    func copiedDataIsPrivate() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.codexPillFolder.appendingPathComponent("snapshots").path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fixture.codexPillFolder.appendingPathComponent("accounts.json").path)

        _ = fixture.migration().run()

        #expect(try fixture.permissions(of: fixture.rusageFolder) == 0o700)
        #expect(try fixture.permissions(of: fixture.rusageFolder.appendingPathComponent("snapshots")) == 0o700)
        #expect(try fixture.permissions(of: fixture.rusageFolder.appendingPathComponent("accounts.json")) == 0o600)
        #expect(try fixture.permissions(of: fixture.rusageFolder.appendingPathComponent("bin/tool")) == 0o700)
    }

    @Test
    func copiesPreferencesRUsageHasNotSet() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        fixture.defaults.set(15, forKey: "refreshIntervalMinutes")

        _ = fixture.migration(preferences: ["refreshIntervalMinutes": 5, "masksEmails": true]).run()

        #expect(fixture.defaults.integer(forKey: "refreshIntervalMinutes") == 15)
        #expect(fixture.defaults.bool(forKey: "masksEmails"))
    }

    @Test(arguments: [
        ("com.raphhgg.rusage", "com.raphhgg.codexpill"),
        ("com.raphhgg.rusage.dev", "com.raphhgg.codexpill.dev"),
        ("com.raphhgg.rusagex", nil),
    ])
    func readsTheCodexPillDomainOfTheSameBuild(bundleIdentifier: String, expected: String?) {
        #expect(CodexPillMigration.legacyDefaultsDomain(for: bundleIdentifier) == expected)
    }
}

private struct MigrationFixture {
    let root: URL
    let suiteName = "CodexPillMigrationTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    var codexPillFolder: URL { root.appendingPathComponent("CodexPill", isDirectory: true) }
    var rusageFolder: URL { root.appendingPathComponent("rusage", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPillMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func migration(preferences: [String: Any] = [:]) -> CodexPillMigration {
        CodexPillMigration(
            legacy: CodexPillLegacyData(folder: codexPillFolder, preferences: preferences),
            folder: rusageFolder,
            defaults: defaults,
            defaultsDomain: suiteName
        )
    }

    func writeCodexPillData() throws {
        try write(codexPillFolder.appendingPathComponent("accounts.json"), #"[{"id":"saved"}]"#)
        try write(codexPillFolder.appendingPathComponent("snapshots/saved.json"), "snapshot")
        try write(codexPillFolder.appendingPathComponent("claude-code-accounts.json"), "claude")
        let tool = codexPillFolder.appendingPathComponent("bin/tool")
        try write(tool, "#!/bin/sh")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    }

    func writeRUsage(_ path: String, _ contents: String) throws {
        try write(rusageFolder.appendingPathComponent(path), contents)
    }

    func rusage(_ path: String) throws -> String {
        try String(contentsOf: rusageFolder.appendingPathComponent(path), encoding: .utf8)
    }

    func listing(of folder: URL) throws -> [String: String] {
        let paths = FileManager.default.subpaths(atPath: folder.path) ?? []
        return try Dictionary(uniqueKeysWithValues: paths.map { path in
            let url = folder.appendingPathComponent(path)
            let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            let mode = String(try permissions(of: url), radix: 8)
            return (path, isDirectory ? "dir \(mode)" : "\(mode) \(try String(contentsOf: url, encoding: .utf8))")
        })
    }

    func permissions(of url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int ?? -1
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func write(_ url: URL, _ contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}
