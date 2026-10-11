import Foundation
import Testing

@testable import Refill

/// Claude Code's Keychain item is `<root>/claude-keychain-item.json`, its global config `<root>/.claude.json`, and
/// Refill's saved accounts `<root>/claude-code-account-<id>.json`. All tokens are fake.
struct ClaudeCodeAccountStoreTests {
    @Test
    func capturingSavesTheSignInOnceAndNamesItAfterTheEmail() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")

        let saved = try fixture.store.captureCurrent()
        #expect(saved.name == "personal@example.com")
        #expect(saved.planName == "max")
        #expect(saved.organizationName == "Personal Org")

        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-2", plan: "pro")
        let again = try fixture.store.captureCurrent()

        #expect(try fixture.store.accounts().map(\.id) == [saved.id])
        #expect(again.name == "personal@example.com")
        #expect(again.planName == "pro")
        #expect(fixture.savedRefreshToken(saved.id) == "fake-personal-refresh-2")
        #expect(try fixture.store.activeAccountID() == saved.id)
    }

    @Test
    func theSameUserInAnotherOrganizationIsAnotherAccount() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")
        let personal = try fixture.store.captureCurrent()
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent(named: "Work")

        #expect(try fixture.store.accounts().map(\.name) == ["personal@example.com", "Work"])
        #expect(personal.id != team.id)
        #expect(try fixture.store.activeAccountID() == team.id)
    }

    @Test
    func switchingReplacesTheClaudeSignInAndKeepsEverythingElse() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")
        let personal = try fixture.store.captureCurrent()

        try fixture.store.activate(team.id)

        let item = try fixture.keychainItem()
        let oauth = try #require(item["claudeAiOauth"] as? [String: Any])
        #expect(oauth["refreshToken"] as? String == "fake-team-refresh-1")
        #expect(oauth["rateLimitTier"] as? String == "fake-tier")
        #expect((item["mcpOAuth"] as? [String: Any])?.keys.sorted() == ["some-server"])
        let config = try fixture.globalConfig()
        #expect((config["oauthAccount"] as? [String: Any])?["emailAddress"] as? String == "team@example.com")
        #expect(config["numStartups"] as? Int == 42)
        #expect((config["projects"] as? [String: Any])?.keys.sorted() == ["/fake/project"])
        #expect(try fixture.store.activeAccountID() == team.id)
        #expect(personal.id != team.id)
    }

    @Test
    func aRotatedRefreshTokenIsSavedBeforeSwitchingAway() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")
        let personal = try fixture.store.captureCurrent()
        try fixture.store.activate(team.id)

        // Claude Code renews the team sign-in and rotates its refresh token.
        try fixture.writeKeychainItem(oauth: .team, refreshToken: "fake-team-refresh-2")
        try fixture.store.activate(personal.id)

        #expect(fixture.savedRefreshToken(team.id) == "fake-team-refresh-2")
        #expect(try fixture.currentRefreshToken() == "fake-personal-refresh-1")

        try fixture.store.activate(team.id)
        #expect(try fixture.currentRefreshToken() == "fake-team-refresh-2")
    }

    @Test
    func aSignInWithoutAnAccountRecordIsNeverGuessedFromItsTokens() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1", recordsAccount: false)
        let before = try fixture.allFiles()

        #expect(throws: ClaudeCodeAccountError.claudeCodeAccountUnknown) { try fixture.store.captureCurrent() }
        #expect(throws: ClaudeCodeAccountError.claudeCodeAccountUnknown) { try fixture.store.activate(team.id) }
        #expect(try fixture.allFiles() == before)
    }

    @Test
    func codexPillNeverRenewsAClaudeSignInItself() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = try #require(FileManager.default.enumerator(at: repository.appendingPathComponent("Sources"), includingPropertiesForKeys: nil))
        let claudeFiles = sources.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.path.contains("Claude") }
        #expect(claudeFiles.count > 5)

        let refreshMarkers = ["refreshToken", "refresh_token", "grant_type", "/oauth/token"]
        let offenders = try claudeFiles.filter { file in
            let source = try String(contentsOf: file, encoding: .utf8)
            return refreshMarkers.contains { source.contains($0) }
        }
        #expect(offenders.map(\.lastPathComponent) == [])
    }

    @Test
    func switchingAwayFromAnUnsavedSignInSavesItFirst() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")

        try fixture.store.activate(team.id)
        #expect(try fixture.currentRefreshToken() == "fake-team-refresh-1")
        let personal = try #require(try fixture.store.accounts().first { $0.id != team.id })

        try fixture.store.activate(personal.id)
        #expect(try fixture.currentRefreshToken() == "fake-personal-refresh-1")
    }

    @Test
    func switchingNeedsClaudeCodeToBeSignedIn() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try FileManager.default.removeItem(at: fixture.keychainFile)

        #expect(throws: ClaudeCodeAccountError.claudeCodeSignedOut) { try fixture.store.activate(team.id) }
        #expect(throws: ClaudeCodeAccountError.claudeCodeSignedOut) { try fixture.store.captureCurrent() }
        #expect(FileManager.default.fileExists(atPath: fixture.keychainFile.path) == false)
    }

    @Test
    func aSignInInTheCredentialsFileIsSwitchedThereAndTheKeychainIsLeftAlone() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        let keychainBefore = try Data(contentsOf: fixture.keychainFile)
        try fixture.writeCredentialsFile(oauth: .personal, refreshToken: "fake-personal-refresh-1")
        try fixture.writeAccountRecord(.personal)
        _ = try fixture.store.captureCurrent()

        try fixture.store.activate(team.id)

        let file = try fixture.json(at: fixture.credentialsFile)
        #expect((file["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String == "fake-team-refresh-1")
        #expect(try Data(contentsOf: fixture.keychainFile) == keychainBefore)
        let permissions = try FileManager.default.attributesOfItem(atPath: fixture.credentialsFile.path)[.posixPermissions]
        #expect(permissions as? Int == 0o600)
    }

    @Test
    func switchingWaitsUntilClaudeCodeQuits() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")
        _ = try fixture.store.captureCurrent()
        let keychainBefore = try Data(contentsOf: fixture.keychainFile)
        let configBefore = try Data(contentsOf: fixture.globalConfigFile)
        fixture.processes.isRunning = true

        #expect(throws: ClaudeCodeAccountError.claudeCodeRunning) { try fixture.store.activate(team.id) }
        #expect(try Data(contentsOf: fixture.keychainFile) == keychainBefore)
        #expect(try Data(contentsOf: fixture.globalConfigFile) == configBefore)

        fixture.processes.isRunning = false
        try fixture.store.activate(team.id)
        #expect(try fixture.store.activeAccountID() == team.id)
    }

    @Test(arguments: SwitchStep.allCases)
    func aFailedSwitchStepPutsEveryFileAndItemBack(_ failingStep: SwitchStep) throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")
        _ = try fixture.store.captureCurrent()
        // Claude Code renewed the personal sign-in, so the switch has a new copy to save first.
        if failingStep == .claudeCodeCredentialsFile {
            try fixture.writeCredentialsFile(oauth: .personal, refreshToken: "fake-personal-refresh-2")
        } else {
            try fixture.writeKeychainItem(oauth: .personal, refreshToken: "fake-personal-refresh-2")
        }
        let before = try fixture.allFiles()

        switch failingStep {
        case .savedAccountItem: fixture.items.failsSaves = true
        case .savedAccountList: try fixture.lock(fixture.catalogFile)
        case .claudeCodeKeychainItem: fixture.keychain.failsUpdates = true
        case .claudeCodeCredentialsFile: try fixture.refuseWrites(in: fixture.credentialsFile.deletingLastPathComponent())
        case .claudeCodeGlobalConfig: try fixture.refuseWrites(in: fixture.globalConfigFile.deletingLastPathComponent())
        }

        #expect(throws: ClaudeCodeAccountError.writeFailed) { try fixture.store.activate(team.id) }
        fixture.allowWrites()
        #expect(try fixture.allFiles() == before)
    }

    @Test
    func aBrokenSavedAccountListIsReportedAndNeverOverwritten() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        try Data("{not json".utf8).write(to: fixture.catalogFile)

        #expect(throws: ClaudeCodeAccountError.savedAccountsUnreadable) { try fixture.store.captureCurrent() }
        #expect(try Data(contentsOf: fixture.catalogFile) == Data("{not json".utf8))
    }

    @Test
    func deletingForgetsTheSavedSignInAndLeavesClaudeCodeAlone() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.store.rename(team.id, to: "Work")
        #expect(try fixture.store.accounts().map(\.name) == ["Work"])

        try fixture.store.delete(team.id)

        #expect(try fixture.store.accounts().isEmpty)
        #expect(fixture.savedRefreshToken(team.id) == nil)
        #expect(try fixture.currentRefreshToken() == "fake-team-refresh-1")
        #expect(throws: ClaudeCodeAccountError.unknownAccount) { try fixture.store.activate(team.id) }
    }

    @Test
    func noTokenAppearsInPrintedAccountsOrSnapshots() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let account = try fixture.store.captureCurrent()
        guard case let .signedIn(snapshot, item) = fixture.store.claudeCode.current(allowingPrompt: true) else {
            Issue.record("Expected a sign-in")
            return
        }
        var dumped = ""
        dump(snapshot, to: &dumped)
        dump(account, to: &dumped)
        dump(item, to: &dumped)

        let printed = [dumped, String(describing: snapshot), String(reflecting: snapshot), String(describing: item), String(describing: account)]
        #expect(printed.filter { $0.contains("fake-team") } == [])
        let catalog = try String(contentsOf: fixture.catalogFile, encoding: .utf8)
        #expect(catalog.contains("fake-team") == false)
    }
}

enum SwitchStep: CaseIterable, Sendable {
    case savedAccountItem
    case savedAccountList
    case claudeCodeKeychainItem
    case claudeCodeCredentialsFile
    case claudeCodeGlobalConfig
}

private enum FakeClaudeAccount {
    case personal
    case team

    var record: [String: Any] {
        switch self {
        case .personal:
            ["accountUuid": "user-uuid", "organizationUuid": "personal-org-uuid", "emailAddress": "personal@example.com",
             "organizationName": "Personal Org"]
        case .team:
            ["accountUuid": "user-uuid", "organizationUuid": "team-org-uuid", "emailAddress": "team@example.com",
             "organizationName": "Team Org"]
        }
    }

    func oauth(refreshToken: String, plan: String) -> [String: Any] {
        ["accessToken": "\(refreshToken)-access", "refreshToken": refreshToken, "expiresAt": 1_791_644_400_000,
         "scopes": ["user:inference", "user:profile"], "subscriptionType": plan, "rateLimitTier": "fake-tier"]
    }
}

private struct ClaudeCodeAccountFixture {
    let root: URL
    let store: ClaudeCodeAccountStore
    let processes = ClaudeCodeProcessProbe()
    let items: FileClaudeCodeAccountItems
    let keychain: FileClaudeCodeKeychain

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCodeAccountFixture-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let codexPill = root.appendingPathComponent("codexpill", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexPill, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["numStartups": 42, "projects": ["/fake/project": ["allowedTools": []]]])
            .write(to: home.appendingPathComponent(".claude.json"))
        items = FileClaudeCodeAccountItems(rootDirectory: codexPill)
        keychain = FileClaudeCodeKeychain(fileURL: codexPill.appendingPathComponent(FileClaudeCodeKeychain.fileName))
        store = ClaudeCodeAccountStore(
            catalogFile: codexPill.appendingPathComponent("claude-code-accounts.json"),
            items: items,
            claudeCode: ClaudeCodeSignInStore(
                configDirectory: home.appendingPathComponent(".claude", isDirectory: true),
                globalConfigFile: ClaudeCodeSignInStore.globalConfigFile(environment: [:], homeDirectory: home),
                keychain: keychain
            ),
            processes: processes
        )
    }

    var keychainFile: URL { root.appendingPathComponent("codexpill/\(FileClaudeCodeKeychain.fileName)") }
    var credentialsFile: URL { root.appendingPathComponent("home/.claude/.credentials.json") }
    var catalogFile: URL { root.appendingPathComponent("codexpill/claude-code-accounts.json") }
    var globalConfigFile: URL { root.appendingPathComponent("home/.claude.json") }

    /// What Claude Code leaves behind after `/login`: the Keychain item, with an MCP sign-in, and the account record.
    func signIn(_ account: FakeClaudeAccount, refreshToken: String, plan: String = "max", recordsAccount: Bool = true) throws {
        try writeKeychainItem(oauth: account, refreshToken: refreshToken, plan: plan)
        if recordsAccount {
            try writeAccountRecord(account)
        } else {
            var config = try globalConfig()
            config["oauthAccount"] = nil
            try JSONSerialization.data(withJSONObject: config).write(to: globalConfigFile)
        }
    }

    func writeKeychainItem(oauth account: FakeClaudeAccount, refreshToken: String, plan: String = "max") throws {
        try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": account.oauth(refreshToken: refreshToken, plan: plan),
            "mcpOAuth": ["some-server": ["accessToken": "fake-mcp-token"]],
        ]).write(to: keychainFile)
    }

    func writeCredentialsFile(oauth account: FakeClaudeAccount, refreshToken: String) throws {
        try JSONSerialization.data(withJSONObject: ["claudeAiOauth": account.oauth(refreshToken: refreshToken, plan: "pro")])
            .write(to: credentialsFile)
    }

    func writeAccountRecord(_ account: FakeClaudeAccount) throws {
        var config = try globalConfig()
        config["oauthAccount"] = account.record
        try JSONSerialization.data(withJSONObject: config).write(to: globalConfigFile)
    }

    func keychainItem() throws -> [String: Any] {
        try json(at: keychainFile)
    }

    func globalConfig() throws -> [String: Any] {
        try json(at: globalConfigFile)
    }

    func currentRefreshToken() throws -> String? {
        (try keychainItem()["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String
    }

    func savedRefreshToken(_ id: UUID) -> String? {
        let data = try? items.read(id)
        let item = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return (item?["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String
    }

    func json(at url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// Every file under the fixture, by path relative to it.
    func allFiles() throws -> [String: Data] {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var files: [String: Data] = [:]
        for case let url as URL in enumerator where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            files[String(url.path.dropFirst(root.path.count))] = try Data(contentsOf: url)
        }
        return files
    }

    /// Makes new files in `directory` fail to save until `allowWrites` runs.
    func refuseWrites(in directory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    }

    /// Makes `file` impossible to replace, even when its folder stays writable.
    func lock(_ file: URL) throws {
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)
    }

    func allowWrites() {
        for directory in ["home", "home/.claude", "codexpill"] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent(directory).path)
        }
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogFile.path)
    }

    func remove() {
        allowWrites()
        try? FileManager.default.removeItem(at: root)
    }
}
