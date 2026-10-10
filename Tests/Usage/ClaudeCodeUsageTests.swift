import Foundation
import Testing

@testable import CodexPill

struct ClaudeCodeUsageTests {
    private let now = Date(timeIntervalSince1970: 1_791_633_600)

    private var currentUsage: UsageProviderReading {
        .snapshot(UsageSnapshot(
            provider: .claude,
            planName: "max",
            windows: [
                UsageWindow(kind: .session, usedPercent: 64, resetsAt: Date(timeIntervalSince1970: 1_791_644_400), durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 21, resetsAt: Date(timeIntervalSince1970: 1_791_968_400), durationMinutes: 10_080),
            ],
            fetchedAt: now
        ))
    }

    @Test
    func aFreshClaudeCodeSignInConnectsWithoutTheBrowserAndDisconnectForgetsTheChoice() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(3_600))
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))

        #expect(await fixture.usage.readUsage(now: now) == .notConnected)
        #expect(fixture.keychainReadPrompts == [])

        #expect(await fixture.usage.connectWithClaudeCodeSignIn(now: now) == true)
        #expect(ClaudeUsageSettingsStore(userDefaults: fixture.defaults).isEnabled == true)
        #expect(await fixture.usage.readUsage(now: now) == currentUsage)

        await fixture.usage.disconnect()

        #expect(ClaudeUsageSettingsStore(userDefaults: fixture.defaults).isEnabled == false)
        #expect(await fixture.usage.readUsage(now: now) == .notConnected)
        #expect(fixture.usageRequestTokens == [ClaudeUsageFixture.fakeAccessToken])
        #expect(fixture.keychainReadPrompts == [false, false])
        #expect(fixture.browserSignInCount == 0)
    }

    @Test
    func anExpiredClaudeCodeSignInNeedsTheBrowserAndOnlyASuccessfulSignInConnects() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.signInToKeychain(expiresAt: now)

        #expect(await fixture.usage.connectWithClaudeCodeSignIn(now: now) == false)
        #expect(fixture.settings.isEnabled == false)

        async let cancelled = fixture.usage.signIn()
        await fixture.waitUntilSignInStarted()
        fixture.finishSignIn(with: .failure(ClaudeSignInError.timedOut))
        #expect(await cancelled == false)
        #expect(fixture.settings.isEnabled == false)
        #expect(fixture.ownSignIn == nil)

        async let signedIn = fixture.usage.signIn()
        await fixture.waitUntilSignInStarted()
        fixture.finishSignIn(with: .success(ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(3_600))))
        #expect(await signedIn == true)
        #expect(fixture.settings.isEnabled == true)
        #expect(fixture.ownSignIn == ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(3_600)))
    }

    @Test
    func codexPillsOwnSignInWinsOverClaudeCodesAndNoSignInAsksForANewOne() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signedOut))

        fixture.signInToKeychain(expiresAt: now)
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInExpired))

        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(3_600))
        _ = await fixture.usage.readUsage(now: now)

        fixture.ownSignIn = ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(3_600))
        #expect(await fixture.usage.readUsage(now: now) == .snapshot(UsageSnapshot(
            provider: .claude,
            planName: nil,
            windows: [
                UsageWindow(kind: .session, usedPercent: 64, resetsAt: Date(timeIntervalSince1970: 1_791_644_400), durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 21, resetsAt: Date(timeIntervalSince1970: 1_791_968_400), durationMinutes: 10_080),
            ],
            fetchedAt: now
        )))
        #expect(fixture.usageRequestTokens == [ClaudeUsageFixture.fakeAccessToken, ClaudeUsageFixture.fakeOwnAccessToken])
    }

    @Test
    func theOwnSignInIsRefreshedFiveMinutesBeforeItExpiresAndTheRotationIsSaved() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))
        fixture.ownSignIn = ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(301))
        let rotated = ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(28_800), rotated: true)
        fixture.refreshResult = .success(rotated)

        _ = await fixture.usage.readUsage(now: now)
        #expect(fixture.refreshRequestTokens == [])

        _ = await fixture.usage.readUsage(now: now.addingTimeInterval(1))
        _ = await fixture.usage.readUsage(now: now.addingTimeInterval(2))

        #expect(fixture.refreshRequestTokens == [ClaudeUsageFixture.fakeOwnRefreshToken])
        #expect(fixture.ownSignIn == rotated)
        #expect(fixture.usageRequestTokens == [
            ClaudeUsageFixture.fakeOwnAccessToken,
            ClaudeUsageFixture.fakeRotatedAccessToken,
            ClaudeUsageFixture.fakeRotatedAccessToken,
        ])
    }

    @Test
    func aRejectedRefreshTokenAsksForANewSignInAndDeletesTheDeadItem() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))
        fixture.ownSignIn = ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(60))
        fixture.refreshResult = .failure(.invalidGrant)

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInExpired))
        #expect(fixture.ownSignIn == nil)
        #expect(fixture.requestCount == 0)
    }

    @Test
    func aRefreshThatCannotReachAnthropicKeepsUsingTheTokenUntilItExpires() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))
        let signIn = ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(60))
        fixture.ownSignIn = signIn
        fixture.refreshResult = .failure(.transport)

        guard case .snapshot = await fixture.usage.readUsage(now: now) else {
            Issue.record("Expected usage with the still-valid token")
            return
        }
        #expect(await fixture.usage.readUsage(now: now.addingTimeInterval(60)) == .unavailable(.unreachable))
        #expect(fixture.ownSignIn == signIn)
        #expect(fixture.requestCount == 1)
    }

    @Test
    func twoReadsAtOnceShareOneRefresh() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))
        fixture.ownSignIn = ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(60))
        fixture.refreshResult = .success(ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(28_800), rotated: true))
        fixture.holdRefreshes()

        async let first = fixture.usage.readUsage(now: now)
        async let second = fixture.usage.readUsage(now: now)
        while !fixture.isRefreshWaiting { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
        fixture.releaseRefresh()
        _ = await (first, second)

        #expect(fixture.refreshRequestTokens == [ClaudeUsageFixture.fakeOwnRefreshToken])
        #expect(fixture.usageRequestTokens == [ClaudeUsageFixture.fakeRotatedAccessToken, ClaudeUsageFixture.fakeRotatedAccessToken])
    }

    @Test
    func disconnectDeletesAndRevokesOnlyCodexPillsOwnSignIn() async {
        let fixture = ClaudeUsageFixture()
        defer { fixture.remove() }
        fixture.settings.isEnabled = true
        fixture.signInToKeychain(expiresAt: now.addingTimeInterval(3_600))
        let claudeCodeItem = fixture.keychainItem
        fixture.ownSignIn = ClaudeUsageFixture.ownSignIn(expiresAt: now.addingTimeInterval(3_600))

        await fixture.usage.disconnect()

        #expect(fixture.settings.isEnabled == false)
        #expect(fixture.ownSignIn == nil)
        #expect(fixture.revokedRefreshTokens == [ClaudeUsageFixture.fakeOwnRefreshToken])
        #expect(fixture.keychainItem == claudeCodeItem)
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

        await fixture.usage.allowKeychainAccess()
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
        let signInDoubles = ClaudeUsageFixture()
        defer { signInDoubles.remove() }
        let usage = ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                claudeCode: ClaudeCredentialsSource(configDirectory: configDirectory, keychain: keychain),
                signInStore: InMemoryClaudeSignInStore(),
                tokenEndpoint: signInDoubles,
                webClient: UsagePerTokenWebClient()
            ),
            signInFlow: signInDoubles,
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
        let work = try #require(try usage.accounts?.captureCurrent())
        try signIn(token: "fake-home-token", organization: "fake-home-org")
        _ = try usage.accounts?.captureCurrent()
        await usage.allowKeychainAccess()
        #expect(await weeklyPercent() == 15)

        try await usage.switchAccount(to: work.id)

        #expect(await weeklyPercent() == 80)
    }
}

/// Answers with a different weekly percent for each fake token, so a test can tell whose limits were read.
private struct UsagePerTokenWebClient: ClaudeUsageWebClient {
    func usage(using token: ClaudeAccessToken) async throws(ClaudeUsageWebError) -> Data {
        let weekly = token.authorizationHeaderValue == "Bearer fake-work-token" ? 80 : 15
        return Data(#"{"seven_day":{"utilization":\#(weekly),"resets_at":null}}"#.utf8)
    }
}

