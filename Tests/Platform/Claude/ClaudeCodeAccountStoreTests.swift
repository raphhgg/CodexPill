import Foundation
import Testing

@testable import CodexPill

/// Runs on the isolated-run seams: Claude Code's Keychain item is `<root>/claude-keychain-item.json`, its global
/// config `<root>/.claude.json`, and CodexPill's saved accounts `<root>/claude-code-account-<id>.json`. All tokens are fake.
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

        #expect(fixture.store.accounts().map(\.id) == [saved.id])
        #expect(again.name == "personal@example.com")
        #expect(again.planName == "pro")
        #expect(fixture.savedRefreshToken(saved.id) == "fake-personal-refresh-2")
        #expect(fixture.store.activeAccountID() == saved.id)
    }

    @Test
    func theSameUserInAnotherOrganizationIsAnotherAccount() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")
        let personal = try fixture.store.captureCurrent()
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent(named: "Work")

        #expect(fixture.store.accounts().map(\.name) == ["personal@example.com", "Work"])
        #expect(personal.id != team.id)
        #expect(fixture.store.activeAccountID() == team.id)
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
        #expect(fixture.store.activeAccountID() == team.id)
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
    func aSignInWithoutAnAccountRecordMatchesByItsRefreshToken() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1", recordsAccount: false)
        let unnamed = try fixture.store.captureCurrent()
        #expect(unnamed.name == "Claude Account")
        #expect(try fixture.store.captureCurrent().id == unnamed.id)

        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")
        _ = try fixture.store.captureCurrent()
        try fixture.store.activate(unnamed.id)

        #expect(try fixture.currentRefreshToken() == "fake-team-refresh-1")
        #expect(try fixture.globalConfig()["oauthAccount"] == nil)
    }

    @Test
    func anUnsavedSignInIsNeverOverwritten() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.signIn(.personal, refreshToken: "fake-personal-refresh-1")

        #expect(throws: ClaudeCodeAccountError.currentSignInNotSaved) { try fixture.store.activate(team.id) }
        #expect(try fixture.currentRefreshToken() == "fake-personal-refresh-1")
        #expect(fixture.store.activeAccountID() == nil)
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
    func deletingForgetsTheSavedSignInAndLeavesClaudeCodeAlone() throws {
        let fixture = try ClaudeCodeAccountFixture()
        defer { fixture.remove() }
        try fixture.signIn(.team, refreshToken: "fake-team-refresh-1")
        let team = try fixture.store.captureCurrent()
        try fixture.store.rename(team.id, to: "Work")
        #expect(fixture.store.accounts().map(\.name) == ["Work"])

        try fixture.store.delete(team.id)

        #expect(fixture.store.accounts().isEmpty)
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
        #expect(String(describing: snapshot) == "ClaudeCodeSignInSnapshot(redacted)")
        let catalog = try String(contentsOf: fixture.catalogFile, encoding: .utf8)
        #expect(catalog.contains("fake-team") == false)
    }
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

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCodeAccountFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["numStartups": 42, "projects": ["/fake/project": ["allowedTools": []]]])
            .write(to: root.appendingPathComponent(".claude.json"))
        store = ClaudeCodeAccountStore(
            catalogFile: root.appendingPathComponent("claude-code-accounts.json"),
            items: ValidationClaudeCodeAccountItems(rootDirectory: root),
            claudeCode: ClaudeCodeSignInStore(
                configDirectory: root.appendingPathComponent(".claude", isDirectory: true),
                globalConfigFile: ClaudeCodeSignInStore.globalConfigFile(environment: [:], homeDirectory: root),
                keychain: ValidationClaudeKeychain(fileURL: root.appendingPathComponent(ValidationClaudeKeychain.fileName))
            )
        )
    }

    var keychainFile: URL { root.appendingPathComponent(ValidationClaudeKeychain.fileName) }
    var credentialsFile: URL { root.appendingPathComponent(".claude/.credentials.json") }
    var catalogFile: URL { root.appendingPathComponent("claude-code-accounts.json") }

    /// What Claude Code leaves behind after `/login`: the Keychain item, with an MCP sign-in, and the account record.
    func signIn(_ account: FakeClaudeAccount, refreshToken: String, plan: String = "max", recordsAccount: Bool = true) throws {
        try writeKeychainItem(oauth: account, refreshToken: refreshToken, plan: plan)
        if recordsAccount {
            try writeAccountRecord(account)
        } else {
            var config = try globalConfig()
            config["oauthAccount"] = nil
            try JSONSerialization.data(withJSONObject: config).write(to: root.appendingPathComponent(".claude.json"))
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
        try JSONSerialization.data(withJSONObject: config).write(to: root.appendingPathComponent(".claude.json"))
    }

    func keychainItem() throws -> [String: Any] {
        try json(at: keychainFile)
    }

    func globalConfig() throws -> [String: Any] {
        try json(at: root.appendingPathComponent(".claude.json"))
    }

    func currentRefreshToken() throws -> String? {
        (try keychainItem()["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String
    }

    func savedRefreshToken(_ id: UUID) -> String? {
        let data = ValidationClaudeCodeAccountItems(rootDirectory: root).read(id)
        let item = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return (item?["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String
    }

    func json(at url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
