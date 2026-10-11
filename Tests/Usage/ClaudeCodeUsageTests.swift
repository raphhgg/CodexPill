import Foundation
import Testing

@testable import Refill

struct ClaudeCodeUsageTests {
    private let now = Date(timeIntervalSince1970: 1_791_633_600)

    @Test
    func readsNothingUntilConnectedAndRemembersTheChoice() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(3_600))
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))

        #expect(await fixture.usage.readUsage(now: now) == .notConnected)
        #expect(fixture.keychainReadPrompts == [])

        await fixture.usage.connect()

        #expect(ClaudeUsageSettingsStore(userDefaults: fixture.defaults).isEnabled == true)
        #expect(await fixture.usage.readUsage(now: now) == .snapshot(UsageSnapshot(
            provider: .claude,
            planName: "max",
            windows: [
                UsageWindow(kind: .session, usedPercent: 64, resetsAt: Date(timeIntervalSince1970: 1_791_644_400), durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 21, resetsAt: Date(timeIntervalSince1970: 1_791_968_400), durationMinutes: 10_080),
            ],
            fetchedAt: now
        )))

        await fixture.usage.disconnect()

        #expect(ClaudeUsageSettingsStore(userDefaults: fixture.defaults).isEnabled == false)
        #expect(await fixture.usage.readUsage(now: now) == .notConnected)
        #expect(fixture.requestCount == 1)
    }

    @Test
    func onlyTheReadRightAfterAUserActionMayShowTheKeychainPrompt() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(3_600), needsPermission: true)
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))
        fixture.settings.isEnabled = true

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.keychainAccessNeeded))
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.keychainAccessNeeded))
        #expect(fixture.requestCount == 0)

        await fixture.usage.connect()
        guard case .snapshot = await fixture.usage.readUsage(now: now) else {
            Issue.record("Expected usage after the user allowed Keychain access")
            return
        }
        _ = await fixture.usage.readUsage(now: now)

        #expect(fixture.keychainReadPrompts == [false, false, true, false])
    }

    @Test
    func anExpiredSignInIsNeverSentToAnthropic() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.signInToKeychain(expiresAt: now)
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInExpired))
        #expect(fixture.requestCount == 0)
    }

    @Test
    func eachAnthropicProblemBecomesOneMenuState() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signedOut))

        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(3_600))
        fixture.response = .failure(.unauthorized)
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInExpired))

        fixture.response = .failure(.forbidden)
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.accessDenied))

        fixture.response = .failure(.httpStatus(503))
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.serviceError))

        fixture.response = .failure(.transport)
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.unreachable))

        fixture.response = .success(Data("<html>".utf8))
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.unexpectedResponse))

        fixture.keychainItem = Data("not json".utf8)
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInUnreadable))
        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(3_600))

        fixture.response = .success(Data(#"{"five_hour":null,"seven_day":null}"#.utf8))
        #expect(await fixture.usage.readUsage(now: now) == .awaitingUsage)
    }

    @Test
    func aRateLimitWaitsForRetryAfterBeforeTheNextRequest() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(7_200))
        fixture.response = .failure(.rateLimited(retryAfter: 900))

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.rateLimited))
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))
        #expect(await fixture.usage.readUsage(now: now.addingTimeInterval(899)) == .unavailable(.rateLimited))
        #expect(fixture.requestCount == 1)

        guard case .snapshot = await fixture.usage.readUsage(now: now.addingTimeInterval(900)) else {
            Issue.record("Expected a request once Retry-After passed")
            return
        }
        #expect(fixture.requestCount == 2)
    }

    @Test
    func aRateLimitWithoutRetryAfterWaitsFiveMinutes() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(7_200))
        fixture.response = .failure(.rateLimited(retryAfter: nil))

        _ = await fixture.usage.readUsage(now: now)
        _ = await fixture.usage.readUsage(now: now.addingTimeInterval(299))
        #expect(fixture.requestCount == 1)

        _ = await fixture.usage.readUsage(now: now.addingTimeInterval(300))
        #expect(fixture.requestCount == 2)
    }

    @Test
    func switchingAccountsChangesWhoseLimitsTheNextReadShows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeSwitchUsage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configDirectory = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let keychain = FileClaudeCodeKeychain(fileURL: root.appendingPathComponent(FileClaudeCodeKeychain.fileName))
        let globalConfig = root.appendingPathComponent(".claude.json")
        let suiteName = "ClaudeSwitchUsage-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let settings = ClaudeUsageSettingsStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        settings.isEnabled = true
        let usage = ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                credentials: ClaudeCredentialsSource(configDirectory: configDirectory, keychain: keychain),
                webClient: UsagePerTokenWebClient()
            ),
            accounts: ClaudeCodeAccountStore(
                catalogFile: root.appendingPathComponent("claude-code-accounts.json"),
                items: FileClaudeCodeAccountItems(rootDirectory: root),
                claudeCode: ClaudeCodeSignInStore(configDirectory: configDirectory, globalConfigFile: globalConfig, keychain: keychain),
                processes: ClaudeCodeProcessProbe()
            )
        )
        func signIn(token: String, organization: String) throws {
            let expiresAt = Int(now.addingTimeInterval(3_600).timeIntervalSince1970 * 1_000)
            try Data(#"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":\#(expiresAt),"subscriptionType":"max"}}"#.utf8)
                .write(to: root.appendingPathComponent(FileClaudeCodeKeychain.fileName))
            try Data(#"{"oauthAccount":{"accountUuid":"fake-user","organizationUuid":"\#(organization)"}}"#.utf8).write(to: globalConfig)
        }
        func weeklyPercent() async -> Int? {
            guard case let .snapshot(snapshot) = await usage.readUsage(now: now) else { return nil }
            return snapshot.window(.weekly)?.usedPercent
        }

        try signIn(token: "fake-work-token", organization: "fake-work-org")
        try usage.accounts?.captureCurrent()
        try signIn(token: "fake-home-token", organization: "fake-home-org")
        try usage.accounts?.captureCurrent()
        await usage.connect()
        #expect(await weeklyPercent() == 15)
        let work = try #require(try await usage.savedAccounts().first { !$0.isActive })

        try await usage.switchAccount(to: work.id)

        #expect(await weeklyPercent() == 80)
        #expect(try await usage.savedAccounts().first { $0.isActive }?.id == work.id)
    }
}

/// Answers with a different weekly percent for each fake token, so a test can tell whose limits were read.
private struct UsagePerTokenWebClient: ClaudeUsageWebClient {
    func usage(using token: ClaudeAccessToken) async throws(ClaudeUsageWebError) -> Data {
        let weekly = token.authorizationHeaderValue == "Bearer fake-work-token" ? 80 : 15
        return Data(#"{"seven_day":{"utilization":\#(weekly),"resets_at":null}}"#.utf8)
    }
}

