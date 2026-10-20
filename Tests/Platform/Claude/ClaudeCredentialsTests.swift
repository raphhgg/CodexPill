import Foundation
import Testing

@testable import rusage

struct ClaudeCredentialsTests {
    /// Only the files of rusage's own sign-in may hold a refresh token, and none of them names Claude Code's sign-in.
    @Test
    func noClaudeCodeSignInIsEverRenewed() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = try #require(FileManager.default.enumerator(at: repository.appendingPathComponent("Sources"), includingPropertiesForKeys: nil))
        let claudeFiles = sources.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.path.contains("Claude") }
        #expect(claudeFiles.count > 5)

        let ownSignInFiles: Set = ["ClaudeOAuth.swift", "ClaudeSignIn.swift", "ClaudeOwnSignIn.swift", "ClaudeTokenEndpoint.swift"]
        let refreshMarkers = ["refreshToken", "refresh_token", "grant_type", "/oauth/token"]
        let claudeCodeMarkers = ["Claude Code-credentials", "SystemClaudeKeychain", "ClaudeCredentialsSource", "ClaudeCredentials("]
        let sourcesByName = try Dictionary(uniqueKeysWithValues: claudeFiles.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) })

        let renewing = sourcesByName.filter { name, source in
            !ownSignInFiles.contains(name) && refreshMarkers.contains { source.contains($0) }
        }
        let ownSignInReadingClaudeCode = sourcesByName.filter { name, source in
            ownSignInFiles.contains(name) && claudeCodeMarkers.contains { source.contains($0) }
        }
        #expect(renewing.keys.sorted() == [])
        #expect(ownSignInReadingClaudeCode.keys.sorted() == [])
        #expect(ownSignInFiles.isSubset(of: sourcesByName.keys))
    }

    @Test
    func readsTheClaudeSignInAndNeverItsRefreshToken() throws {
        let credentials = try #require(try ClaudeCredentials(json: Data(#"""
        {"claudeAiOauth":{"accessToken":"fake-claude-access-token","refreshToken":"fake-claude-refresh-token",
         "expiresAt":1791644400000,"scopes":["user:inference","user:profile"],"subscriptionType":"max"},
         "mcpOAuth":{"some-server":{"accessToken":"fake-mcp-token"}}}
        """#.utf8)))

        #expect(credentials.accessToken.authorizationHeaderValue == "Bearer fake-claude-access-token")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_791_644_400))
        #expect(credentials.subscriptionType == "max")
        #expect(credentials.isExpired(at: Date(timeIntervalSince1970: 1_791_644_399)) == false)
        #expect(credentials.isExpired(at: Date(timeIntervalSince1970: 1_791_644_400)) == true)
    }

    @Test(arguments: [
        (#""subscriptionType":"max","rateLimitTier":"default_claude_max_20x""#, "max_20x"),
        (#""subscriptionType":"max","rateLimitTier":"default_claude_max_5x""#, "max_5x"),
        (#""subscriptionType":"pro","rateLimitTier":"default_claude_ai""#, "pro"),
        (#""subscriptionType":"pro""#, "pro"),
    ])
    func thePlanCarriesTheMaxMultiplierWhenClaudeCodeRecordedOne(fields: String, planName: String) throws {
        let json = #"{"claudeAiOauth":{"accessToken":"fake-claude-access-token","# + fields + "}}"
        let credentials = try #require(try ClaudeCredentials(json: Data(json.utf8)))

        #expect(credentials.planName == planName)
    }

    @Test(arguments: [
        (#"{"oauthAccount":{"organizationRateLimitTier":"default_claude_max_20x"}}"#, "Max x20"),
        (#"{"oauthAccount":{"userRateLimitTier":"default_claude_max_20x"}}"#, "Max x20"),
        (#"{"oauthAccount":{"emailAddress":"person@example.com"}}"#, "Max x5"),
        (nil, "Max x5"),
    ])
    func thePlanTagFollowsClaudeCodesAccountRecordOverTheTierFrozenInTheCredentials(globalConfig: String?, tag: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudePlanTier-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"claudeAiOauth":{"accessToken":"fake-claude-access-token","subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}"#.utf8)
            .write(to: root.appendingPathComponent(".credentials.json"))
        if let globalConfig {
            try Data(globalConfig.utf8).write(to: root.appendingPathComponent(".claude.json"))
        }
        let source = ClaudeCredentialsSource(configDirectory: root, keychain: nil, globalConfigFile: root.appendingPathComponent(".claude.json"))

        guard case let .credentials(credentials) = source.lookup(allowingPrompt: false) else {
            Issue.record("expected credentials")
            return
        }
        #expect(planTag(for: .claude, planName: credentials.planName) == tag)
    }

    @Test
    func theEmailComesFromClaudeCodesAccountRecord() throws {
        let credentials = Data(#"{"claudeAiOauth":{"accessToken":"fake-claude-access-token","subscriptionType":"max"}}"#.utf8)
        let globalConfig = Data(#"{"oauthAccount":{"emailAddress":"person@example.com"}}"#.utf8)

        #expect(try ClaudeCredentials(json: credentials, globalConfig: globalConfig)?.email == "person@example.com")
        #expect(try ClaudeCredentials(json: credentials)?.email == nil)
    }

    @Test
    func anItemWithOnlyMCPSignInsIsSignedOutAndGarbageIsAnError() throws {
        #expect(try ClaudeCredentials(json: Data(#"{"mcpOAuth":{"some-server":{"accessToken":"fake-mcp-token"}}}"#.utf8)) == nil)
        #expect(try ClaudeCredentials(json: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil)
        #expect(throws: (any Error).self) { try ClaudeCredentials(json: Data("not json".utf8)) }
    }

    @Test
    func theTokenNeverAppearsWhenCredentialsOrTheRequestArePrinted() throws {
        let credentials = try #require(try ClaudeCredentials(json: Data(
            ClaudeUsageFixture.credentialsJSON(expiresAt: Date(timeIntervalSince1970: 1_791_644_400)).utf8
        )))
        let request = ClaudeUsageAPI.request(using: credentials.accessToken)
        var dumped = ""
        dump(credentials, to: &dumped)

        let printed = [
            String(describing: credentials.accessToken),
            String(reflecting: credentials.accessToken),
            String(describing: credentials),
            String(reflecting: credentials),
            dumped,
            String(describing: request),
            String(reflecting: request),
        ]
        #expect(printed.filter { $0.contains("fake-claude-access-token") || $0.contains("fake-claude-refresh-token") } == [])
    }

    @Test
    func theCredentialsFileWinsAndTheKeychainIsTheFallback() throws {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        let source = ClaudeCredentialsSource(configDirectory: fixture.configDirectory, keychain: fixture)
        fixture.signInToKeychain(expiresAt: Date(timeIntervalSince1970: 1_791_644_400))

        guard case let .credentials(fromKeychain) = source.lookup(allowingPrompt: false) else {
            Issue.record("Expected the Keychain sign-in when there is no credentials file")
            return
        }
        #expect(fromKeychain.expiresAt == Date(timeIntervalSince1970: 1_791_644_400))
        #expect(fixture.keychainReadPrompts == [false])

        try fixture.writeCredentialsFile(
            ClaudeUsageFixture.credentialsJSON(expiresAt: Date(timeIntervalSince1970: 1_791_968_400), subscriptionType: "pro")
        )
        guard case let .credentials(fromFile) = source.lookup(allowingPrompt: false) else {
            Issue.record("Expected the file sign-in")
            return
        }
        #expect(fromFile.subscriptionType == "pro")
        #expect(fixture.keychainReadPrompts == [false])
    }

    @Test
    func keychainProblemsBecomeOneLookupEach() {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        let source = ClaudeCredentialsSource(configDirectory: fixture.configDirectory, keychain: fixture)

        #expect(describe(source.lookup(allowingPrompt: false)) == "signedOut")

        fixture.keychainItem = Data(#"{"mcpOAuth":{"some-server":{}}}"#.utf8)
        #expect(describe(source.lookup(allowingPrompt: false)) == "signedOut")

        fixture.signInToKeychain(expiresAt: Date(timeIntervalSince1970: 1_791_644_400), needsPermission: true)
        #expect(describe(source.lookup(allowingPrompt: false)) == "keychainAccessNeeded")
        #expect(describe(source.lookup(allowingPrompt: true)) == "credentials")

        fixture.keychainItem = Data("not json".utf8)
        #expect(describe(source.lookup(allowingPrompt: false)) == "unreadable")
        #expect(fixture.keychainReadPrompts == [false, false, false, true, false])
    }

    @Test
    func aBrokenCredentialsFileIsReportedInsteadOfSkipped() throws {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        let source = ClaudeCredentialsSource(configDirectory: fixture.configDirectory, keychain: fixture)
        fixture.signInToKeychain(expiresAt: Date(timeIntervalSince1970: 1_791_644_400))

        try fixture.writeCredentialsFile("{not json")
        #expect(describe(source.lookup(allowingPrompt: false)) == "unreadable")

        try fixture.writeCredentialsFile(ClaudeUsageFixture.credentialsJSON(expiresAt: Date(timeIntervalSince1970: 1_791_644_400)))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.credentialsFileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.credentialsFileURL.path) }
        #expect(describe(source.lookup(allowingPrompt: false)) == "unreadable")
        #expect(fixture.keychainReadPrompts == [])
    }

    private func describe(_ lookup: ClaudeCredentialsLookup) -> String {
        switch lookup {
        case .signedOut: "signedOut"
        case .keychainAccessNeeded: "keychainAccessNeeded"
        case .unreadable: "unreadable"
        case .credentials: "credentials"
        }
    }
}
