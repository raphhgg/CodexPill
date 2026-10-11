import Foundation
import Testing

@testable import CodexPill

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

        #expect(CursorUsageSettingsStore(userDefaults: fixture.defaults).isEnabled == true)
        _ = await fixture.usage.readUsage(now: now)
        #expect(fixture.requestCount == 1)

        await fixture.usage.disconnect()

        #expect(CursorUsageSettingsStore(userDefaults: fixture.defaults).isEnabled == false)
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
    func onDemandSpendKeepsItsCapOrNone() async {
        let capped = await connectedReading(summary: CursorUsageFixture.proPlanWithCappedOnDemand)
        let uncapped = await connectedReading(summary: #"""
        {"billingCycleStart":"2026-09-30T15:23:08.000Z","billingCycleEnd":"2026-10-30T15:23:08.000Z","membershipType":"pro",
         "individualUsage":{"plan":{"enabled":true,"totalPercentUsed":100},"onDemand":{"enabled":true,"used":1234,"limit":null}}}
        """#)

        #expect(spend(in: capped) == UsageSpend(usedUSD: Decimal(string: "12.34")!, limitUSD: 50))
        #expect(spend(in: uncapped) == UsageSpend(usedUSD: Decimal(string: "12.34")!, limitUSD: nil))
    }

    @Test
    func spendReadsAsDollarsWithTheCapWhenSet() {
        let locale = Locale(identifier: "en_US")

        #expect(onDemandSpendText(UsageSpend(usedUSD: Decimal(string: "12.34")!, limitUSD: 50), locale: locale) == "On-demand: $12.34 of $50.00")
        #expect(onDemandSpendText(UsageSpend(usedUSD: Decimal(string: "12.34")!, limitUSD: nil), locale: locale) == "On-demand: $12.34")
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

    @Test
    func switchingGoesThroughTheSavedAccountsAndQuitsCursorFirst() async throws {
        let workToken = CursorAccessTokenFixtures.jwt(subject: "auth0|user_work", expiresAt: now)
        let homeToken = CursorAccessTokenFixtures.jwt(subject: "auth0|user_home", expiresAt: now)
        let harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertText(homeToken)
        harness.close()
        let store = CursorAccountStoreHarness()
        let app = CursorAppProcessProbe()
        let work = CursorSavedAccount(
            id: UUID(),
            signIn: try #require(CursorSignIn(values: [CursorSignIn.accessTokenKey: .text(workToken)]))
        )
        try store.save([work])
        let fixture = CursorUsageFixture()
        defer { fixture.remove() }
        let usage = CursorUsage(
            settings: fixture.settings,
            client: fixture.usage.client,
            accounts: CursorAccounts(database: CursorStateDatabase(url: harness.databaseURL), store: store, app: app)
        )

        try await usage.switchAccount(to: work.id)

        #expect(app.events == [.quit, .open])
        #expect(try CursorStateDatabaseTokenSource(databaseURL: harness.databaseURL).lookup().userID == "user_work")
        #expect(try store.load().count == 2)
        #expect(try await usage.savedAccounts().first { $0.isActive }?.id == work.id)
    }

    @Test
    func switchingIsUnavailableWithoutSavedAccounts() async {
        let fixture = CursorUsageFixture()
        defer { fixture.remove() }

        await #expect(throws: ProviderNotice(title: "Switching unavailable", detail: "This build can't switch accounts.")) {
            try await fixture.usage.switchAccount(to: UUID())
        }
    }

    private func connectedReading(summary: String) async -> UsageProviderReading {
        let now = now
        let fixture = CursorUsageFixture(now: { now })
        defer { fixture.remove() }
        await fixture.usage.connect()
        fixture.signIn(expiresAt: now.addingTimeInterval(3_600), summary: summary)
        return await fixture.usage.readUsage(now: now)
    }

    private func spend(in reading: UsageProviderReading) -> UsageSpend? {
        guard case let .snapshot(snapshot) = reading else { return nil }
        return snapshot.spend
    }
}

private extension CursorAccessTokenLookup {
    var userID: String? {
        guard case let .token(token) = self else { return nil }
        return token.userID
    }
}
