import Foundation
import Testing

@testable import Refill

struct CodexPillMigrationTests {
    @Test
    func copiesCodexPillFolderWhenRefillHasNone() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()

        #expect(fixture.migration().run() == .copied)

        #expect(try fixture.refill("accounts.json") == #"[{"id":"saved"}]"#)
        #expect(try fixture.refill("snapshots/saved.json") == "snapshot")
        #expect(try fixture.refill("claude-code-accounts.json") == "claude")
        #expect(try fixture.refill("bin/tool") == "#!/bin/sh")
    }

    @Test
    func replacesAnEmptyRefillCatalogWithCodexPillData() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        try fixture.writeRefill("accounts.json", "[]\n")
        try FileManager.default.createDirectory(at: fixture.refillFolder.appendingPathComponent("snapshots"), withIntermediateDirectories: true)

        #expect(fixture.migration().run() == .copied)

        #expect(try fixture.refill("accounts.json") == #"[{"id":"saved"}]"#)
        #expect(try fixture.refill("snapshots/saved.json") == "snapshot")
    }

    @Test(arguments: [
        ("accounts.json", #"[{"id":"refill"}]"#),
        ("snapshots/refill.json", "refill snapshot"),
        ("claude-code-accounts.json", "refill claude"),
    ])
    func leavesRealRefillDataUntouched(path: String, contents: String) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        fixture.keychain.items["CodexPill Cursor accounts"] = ["Cursor": Data("old cursor".utf8)]
        try fixture.writeRefill(path, contents)

        #expect(fixture.migration().run() == .keptRefillData)

        #expect(try fixture.refill(path) == contents)
        #expect(!FileManager.default.fileExists(atPath: fixture.refillFolder.appendingPathComponent("bin").path))
        #expect(fixture.keychain.items["Refill Cursor accounts"] == nil)
    }

    @Test
    func secondRunChangesNothing() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        #expect(fixture.migration().run() == .copied)
        try fixture.writeRefill("accounts.json", "[]")
        try FileManager.default.removeItem(at: fixture.refillFolder.appendingPathComponent("snapshots"))

        #expect(fixture.migration().run() == .alreadyRan)

        #expect(try fixture.refill("accounts.json") == "[]")
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

        #expect(try fixture.permissions(of: fixture.refillFolder) == 0o700)
        #expect(try fixture.permissions(of: fixture.refillFolder.appendingPathComponent("snapshots")) == 0o700)
        #expect(try fixture.permissions(of: fixture.refillFolder.appendingPathComponent("accounts.json")) == 0o600)
        #expect(try fixture.permissions(of: fixture.refillFolder.appendingPathComponent("bin/tool")) == 0o700)
    }

    @Test
    func copiesPreferencesRefillHasNotSet() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        fixture.defaults.set(15, forKey: "refreshIntervalMinutes")

        _ = fixture.migration(preferences: ["refreshIntervalMinutes": 5, "masksEmails": true]).run()

        #expect(fixture.defaults.integer(forKey: "refreshIntervalMinutes") == 15)
        #expect(fixture.defaults.bool(forKey: "masksEmails"))
    }

    @Test
    func copiesKeychainItemsRefillDoesNotHave() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        let first = UUID().uuidString, second = UUID().uuidString
        fixture.keychain.items["CodexPill Claude Code account"] = [first: Data("old first".utf8), second: Data("old second".utf8)]
        fixture.keychain.items["Refill Claude Code account"] = [second: Data("refill second".utf8)]
        fixture.keychain.items["CodexPill Cursor accounts"] = ["Cursor": Data("old cursor".utf8)]

        #expect(fixture.migration().run() == .copied)

        #expect(fixture.keychain.items["Refill Claude Code account"] == [first: Data("old first".utf8), second: Data("refill second".utf8)])
        #expect(fixture.keychain.items["Refill Cursor accounts"] == ["Cursor": Data("old cursor".utf8)])
        #expect(fixture.keychain.items["CodexPill Claude Code account"]?.count == 2)
    }

    @Test
    func reportsAnItemThatCouldNotBeReadAndCopiesTheRest() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try fixture.writeCodexPillData()
        fixture.keychain.items["CodexPill Claude Code account"] = ["denied": Data("old".utf8)]
        fixture.keychain.items["CodexPill Cursor accounts"] = ["Cursor": Data("old cursor".utf8)]
        fixture.keychain.deniedAccounts = ["denied"]

        #expect(fixture.migration().run() == .failed)

        #expect(fixture.keychain.items["Refill Cursor accounts"] == ["Cursor": Data("old cursor".utf8)])
        #expect(try fixture.refill("accounts.json") == #"[{"id":"saved"}]"#)
        #expect(fixture.migration().run() == .alreadyRan)
    }

    @Test(arguments: [
        ("com.raphhgg.refill", "com.raphhgg.codexpill"),
        ("com.raphhgg.refill.dev", "com.raphhgg.codexpill.dev"),
        ("com.raphhgg.refillx", nil),
    ])
    func readsTheCodexPillDomainOfTheSameBuild(bundleIdentifier: String, expected: String?) {
        #expect(CodexPillMigration.legacyDefaultsDomain(for: bundleIdentifier) == expected)
    }
}

private final class InMemoryGenericPasswords: GenericPasswordStore {
    var items: [String: [String: Data]] = [:]
    var deniedAccounts: Set<String> = []

    func accounts(service: String) throws -> [String] {
        items[service, default: [:]].keys.sorted()
    }

    func read(service: String, account: String) throws -> Data {
        guard !deniedAccounts.contains(account), let data = items[service]?[account] else {
            throw KeychainStatusError(status: errSecAuthFailed)
        }
        return data
    }

    func add(_ data: Data, service: String, account: String) throws {
        items[service, default: [:]][account] = items[service]?[account] ?? data
    }
}

private struct MigrationFixture {
    let root: URL
    let suiteName = "CodexPillMigrationTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let keychain = InMemoryGenericPasswords()

    var codexPillFolder: URL { root.appendingPathComponent("CodexPill", isDirectory: true) }
    var refillFolder: URL { root.appendingPathComponent("Refill", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPillMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func migration(preferences: [String: Any] = [:]) -> CodexPillMigration {
        CodexPillMigration(
            legacy: CodexPillLegacyData(folder: codexPillFolder, preferences: preferences),
            folder: refillFolder,
            defaults: defaults,
            defaultsDomain: suiteName,
            keychain: keychain
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

    func writeRefill(_ path: String, _ contents: String) throws {
        try write(refillFolder.appendingPathComponent(path), contents)
    }

    func refill(_ path: String) throws -> String {
        try String(contentsOf: refillFolder.appendingPathComponent(path), encoding: .utf8)
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
