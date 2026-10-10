import Foundation
import Testing

@testable import CodexPill

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

        fixture.usage.disconnect()

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

        fixture.response = .failure(.transport)
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.readFailed))

        fixture.response = .success(Data("<html>".utf8))
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.readFailed))

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

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.readFailed))
        fixture.response = .success(Data(ClaudeUsageFixture.usageResponse.utf8))
        #expect(await fixture.usage.readUsage(now: now.addingTimeInterval(899)) == .unavailable(.readFailed))
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
}
