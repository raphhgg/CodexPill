import Foundation
import Testing

@testable import rusage

struct CursorUsageSummaryParserTests {
    private let fetchedAt = Date(timeIntervalSince1970: 1_791_000_000)

    @Test
    func proPlanFixtureMapsToSnapshot() throws {
        let snapshot = try CursorUsageSummaryParser.parse(CursorUsageSummaryFixtures.proPlan, fetchedAt: fetchedAt)

        #expect(snapshot == CursorUsageSnapshot(
            planName: "pro",
            includedUsagePercent: 82.29,
            onDemand: nil,
            billingCycle: DateInterval(
                start: try Date("2026-09-30T15:23:08Z", strategy: .iso8601),
                end: try Date("2026-10-30T15:23:08Z", strategy: .iso8601)
            ),
            fetchedAt: fetchedAt
        ))
    }

    @Test
    func enabledOnDemandConvertsCentsToDollars() throws {
        let snapshot = try parse("""
        { "individualUsage": { "onDemand": { "enabled": true, "used": 1234, "limit": 5000 } } }
        """)

        #expect(snapshot.onDemand == CursorOnDemandSpend(usedUSD: Decimal(string: "12.34")!, limitUSD: 50))
    }

    @Test
    func enabledOnDemandWithoutLimitHasNoCap() throws {
        let snapshot = try parse("""
        { "individualUsage": { "onDemand": { "enabled": true, "used": 0, "limit": null } } }
        """)

        #expect(snapshot.onDemand == CursorOnDemandSpend(usedUSD: 0, limitUSD: nil))
    }

    @Test
    func missingTotalPercentFallsBackToUsedOverLimit() throws {
        let snapshot = try parse("""
        { "individualUsage": { "plan": { "enabled": true, "used": 500, "limit": 2000 } } }
        """)

        #expect(snapshot.includedUsagePercent == 25)
    }

    @Test
    func unlimitedPlanReportsNoPercent() throws {
        let snapshot = try parse("""
        { "isUnlimited": true, "individualUsage": { "plan": { "enabled": true, "totalPercentUsed": 40 } } }
        """)

        #expect(snapshot.includedUsagePercent == nil)
    }

    @Test
    func nonObjectBodyThrowsUnexpectedShape() {
        #expect(throws: CursorUsageSummaryParser.ParseError.unexpectedShape) {
            try parse("[]")
        }
    }

    private func parse(_ json: String) throws -> CursorUsageSnapshot {
        try CursorUsageSummaryParser.parse(Data(json.utf8), fetchedAt: fetchedAt)
    }
}
