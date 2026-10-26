import Foundation
import Testing

@testable import RUsage

struct CursorUsageTests {
    private let now = CursorAccessTokenFixtures.referenceDate
    private let cycleEnd = Date(timeIntervalSince1970: 1_793_373_788)

    @Test
    func readsNothingUntilConnectedAndRemembersTheChoice() async {
        let now = now
        let fixture = CursorUsageFixture(now: { now })
        defer { fixture.remove() }
        fixture.signIn(expiresAt: now.addingTimeInterval(3_600), summary: CursorUsageFixture.proPlanWithCappedOnDemand)

        #expect(await fixture.usage.readUsage(now: now) == .notConnected)
        #expect(fixture.requestCount == 0)

        await fixture.usage.connect()

        #expect(Preferences(userDefaults: fixture.defaults).load(CursorSettings.self).isConnected == true)
        _ = await fixture.usage.readUsage(now: now)
        #expect(fixture.requestCount == 1)

        await fixture.usage.disconnect()

        #expect(Preferences(userDefaults: fixture.defaults).load(CursorSettings.self).isConnected == false)
        #expect(await fixture.usage.readUsage(now: now) == .notConnected)
    }

    @Test
    func percentComesFromCursorsHeadlineNotFromDollarsWhenBonusCreditApplies() async {
        let reading = await connectedReading(summary: #"""
        {"billingCycleStart":"2026-09-30T15:23:08.000Z","billingCycleEnd":"2026-10-30T15:23:08.000Z","membershipType":"pro","isUnlimited":false,
         "individualUsage":{"plan":{"enabled":true,"used":2000,"limit":2000,"totalPercentUsed":82.29},"onDemand":{"enabled":false,"used":0,"limit":null}}}
        """#)

        #expect(reading == .snapshot(UsageSnapshot(
            provider: .cursor,
            planName: "pro",
            windows: [UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: cycleEnd, durationMinutes: 43_200)],
            fetchedAt: now
        )))
    }

    @Test
    func anUnlimitedPlanHasNoBillingCycleMeterRatherThanZeroPercent() async {
        let reading = await connectedReading(summary: #"""
        {"billingCycleStart":"2026-09-30T15:23:08.000Z","billingCycleEnd":"2026-10-30T15:23:08.000Z","membershipType":"enterprise","isUnlimited":true,
         "individualUsage":{"plan":{"enabled":true,"totalPercentUsed":0}}}
        """#)

        #expect(reading == .snapshot(UsageSnapshot(provider: .cursor, planName: "enterprise", windows: [], fetchedAt: now)))
    }

    @Test
    func onDemandSpendIsExtraUsageWithItsCapOrNone() async {
        let capped = await connectedReading(summary: CursorUsageFixture.proPlanWithCappedOnDemand)
        let uncapped = await connectedReading(summary: #"""
        {"billingCycleStart":"2026-09-30T15:23:08.000Z","billingCycleEnd":"2026-10-30T15:23:08.000Z","membershipType":"pro",
         "individualUsage":{"plan":{"enabled":true,"totalPercentUsed":100},"onDemand":{"enabled":true,"used":1234,"limit":null}}}
        """#)

        #expect(credits(in: capped) == .extraUsage(spent: Decimal(string: "12.34")!, limit: 50, currencyCode: "USD"))
        #expect(credits(in: uncapped) == .extraUsage(spent: Decimal(string: "12.34")!, limit: nil, currencyCode: "USD"))
    }

    @Test
    func disabledOnDemandHasNoCredits() async {
        let reading = await connectedReading(summary: #"""
        {"billingCycleStart":"2026-09-30T15:23:08.000Z","billingCycleEnd":"2026-10-30T15:23:08.000Z","membershipType":"pro",
         "individualUsage":{"plan":{"enabled":true,"totalPercentUsed":100},"onDemand":{"enabled":false,"used":0,"limit":null}}}
        """#)

        guard case let .snapshot(snapshot) = reading else {
            Issue.record("Expected a snapshot, got \(reading)")
            return
        }
        #expect(snapshot.windows.map(\.usedPercent) == [100])
        #expect(snapshot.credits == nil)
    }

    @Test
    func eachCursorProblemBecomesOneMenuState() async {
        let now = now
        let fixture = CursorUsageFixture(now: { now })
        defer { fixture.remove() }
        await fixture.usage.connect()

        fixture.tokenLookup = .cursorNotInstalled
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.notInstalled))

        fixture.tokenLookup = .signedOut
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signedOut))

        fixture.databaseError = .sqlite(code: 11)
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInUnreadable))
        fixture.databaseError = .busy
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInBusy))
        fixture.databaseError = nil

        fixture.signIn(expiresAt: now.addingTimeInterval(30), summary: CursorUsageFixture.proPlanWithCappedOnDemand)
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInExpired))

        fixture.signIn(expiresAt: now.addingTimeInterval(3_600), summary: "")
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

        fixture.response = .failure(.rateLimited(retryAfter: 60))
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.rateLimited))
    }

    private func connectedReading(summary: String) async -> UsageProviderReading {
        let now = now
        let fixture = CursorUsageFixture(now: { now })
        defer { fixture.remove() }
        await fixture.usage.connect()
        fixture.signIn(expiresAt: now.addingTimeInterval(3_600), summary: summary)
        return await fixture.usage.readUsage(now: now)
    }

    private func credits(in reading: UsageProviderReading) -> UsageCredits? {
        guard case let .snapshot(snapshot) = reading else { return nil }
        return snapshot.credits
    }
}

private extension CursorAccessTokenLookup {
    var userID: String? {
        guard case let .token(token, _) = self else { return nil }
        return token.userID
    }
}
