import Foundation
import Testing

@testable import CodexPill

struct ClaudeCredentialsTests {
    @Test
    func readsTheClaudeSignInAndNeverItsRefreshToken() throws {
        let credentials = try #require(ClaudeCredentials(json: Data(#"""
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

    @Test
    func anItemWithOnlyMCPSignInsIsSignedOut() {
        #expect(ClaudeCredentials(json: Data(#"{"mcpOAuth":{"some-server":{"accessToken":"fake-mcp-token"}}}"#.utf8)) == nil)
        #expect(ClaudeCredentials(json: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil)
        #expect(ClaudeCredentials(json: Data("not json".utf8)) == nil)
    }

    @Test
    func theTokenNeverAppearsWhenCredentialsOrTheRequestArePrinted() throws {
        let credentials = try #require(ClaudeCredentials(json: Data(
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
        #expect(String(describing: credentials.accessToken) == "ClaudeAccessToken(redacted)")
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
        #expect(fixture.keychainReadPrompts == [false, false, false, true])
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
