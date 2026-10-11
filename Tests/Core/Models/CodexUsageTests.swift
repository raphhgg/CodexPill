import Foundation
import Testing

@testable import CodexPill

struct CodexUsageTests {
    private let fetchedAt = Date(timeIntervalSince1970: 2_000_000_100)

    @Test
    func currentPayloadMapsPrimaryAndSecondaryToSessionAndWeekly() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "limitId": "codex",
            "planType": "team",
            "primary": { "usedPercent": 21, "resetsAt": 2000000000, "windowDurationMins": 300 },
            "secondary": { "usedPercent": 34, "resetsAt": 2000500000, "windowDurationMins": 10080 }
          }
        }
        """)

        #expect(usage == UsageSnapshot(
            provider: .codex,
            planName: "team",
            windows: [
                UsageWindow(
                    kind: .session,
                    usedPercent: 21,
                    resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
                    durationMinutes: 300
                ),
                UsageWindow(
                    kind: .weekly,
                    usedPercent: 34,
                    resetsAt: Date(timeIntervalSince1970: 2_000_500_000),
                    durationMinutes: 10_080
                ),
            ],
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_100)
        ))
    }

    @Test
    func weeklyOnlyPrimaryWindowHasNoSessionWindow() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "planType": "free",
            "primary": { "usedPercent": 7, "resetsAt": 2000500000, "windowDurationMins": 10080 }
          }
        }
        """)

        #expect(usage.planName == "free")
        #expect(usage.window(.session) == nil)
        #expect(usage.windows == [
            UsageWindow(
                kind: .weekly,
                usedPercent: 7,
                resetsAt: Date(timeIntervalSince1970: 2_000_500_000),
                durationMinutes: 10_080
            ),
        ])
    }

    @Test
    func swappedDurationsAreClassifiedByDurationNotPosition() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "planType": "plus",
            "primary": { "usedPercent": 60, "resetsAt": 2000500000, "windowDurationMins": 10080 },
            "secondary": { "usedPercent": 15, "resetsAt": 2000000000, "windowDurationMins": 300 }
          }
        }
        """)

        #expect(usage.window(.session)?.usedPercent == 15)
        #expect(usage.window(.session)?.durationMinutes == 300)
        #expect(usage.window(.weekly)?.usedPercent == 60)
        #expect(usage.window(.weekly)?.durationMinutes == 10_080)
    }

    @Test
    func weeklyWindowWithinAnHourOfSevenDaysCountsAsWeekly() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "planType": "prolite",
            "primary": { "usedPercent": 7, "resetsAt": 2000000000, "windowDurationMins": 299 },
            "secondary": { "usedPercent": 1, "resetsAt": 2000500000, "windowDurationMins": 10020 }
          }
        }
        """)

        #expect(usage.planName == "prolite")
        #expect(usage.window(.session)?.usedPercent == 7)
        #expect(usage.window(.weekly)?.usedPercent == 1)
    }

    @Test
    func freePlanThirtyDayWindowIsMonthly() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "planType": "free",
            "secondary": { "usedPercent": 0, "windowDurationMins": 43200, "resetsAt": 2002592000 }
          }
        }
        """)

        #expect(usage.displayedWindows.map(\.kind.title) == ["Monthly"])
    }

    @Test
    func proPlanSevenDayWindowIsWeekly() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "planType": "pro",
            "primary": { "usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 2000500000 }
          }
        }
        """)

        #expect(usage.displayedWindows.map(\.kind.title) == ["Weekly"])
    }

    @Test
    func fiveHourAndSevenDayWindowsAreSessionThenWeekly() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "planType": "plus",
            "primary": { "usedPercent": 60, "windowDurationMins": 10080, "resetsAt": 2000500000 },
            "secondary": { "usedPercent": 15, "windowDurationMins": 300, "resetsAt": 2000000000 }
          }
        }
        """)

        #expect(usage.displayedWindows.map(\.kind.title) == ["Session", "Weekly"])
    }

    @Test(arguments: [
        (240, "Session"), (360, "Session"),
        (10_020, "Weekly"), (10_140, "Weekly"),
        (40_260, "Monthly"), (43_200, "Monthly"), (44_640, "Monthly"), (44_700, "Monthly"),
        (239, "4 hours"), (361, "6 hours"), (10_019, "7 days"), (11_520, "8 days"),
        (44_701, "31 days"), (2_160, "36 hours"), (90, "90 minutes"),
    ])
    func windowIsTitledByItsLength(durationMinutes: Int, title: String) throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "primary": { "usedPercent": 9, "resetsAt": 2000000000, "windowDurationMins": \(durationMinutes) }
          }
        }
        """)

        #expect(usage.displayedWindows.map(\.kind.title) == [title])
    }

    @Test
    func mergingTwoReadsKeepsAMonthlyWindow() throws {
        let first = try usage(fromAppServerJSON: """
        { "rateLimits": { "planType": "free", "secondary": { "usedPercent": 3, "windowDurationMins": 43200 } } }
        """)
        let second = try usage(fromAppServerJSON: """
        { "rateLimits": { "planType": "free", "secondary": { "usedPercent": 4, "windowDurationMins": 43200 } } }
        """)

        let merged = try #require(mergeAppServerUsage(previous: first, current: second))

        #expect(merged.windows == [UsageWindow(kind: .monthly, usedPercent: 4, resetsAt: nil, durationMinutes: 43_200)])
    }

    @Test
    func twoSessionLengthWindowsKeepOnlyTheFirst() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "primary": { "usedPercent": 11, "resetsAt": 2000000000, "windowDurationMins": 300 },
            "secondary": { "usedPercent": 22, "resetsAt": 2000000000, "windowDurationMins": 300 }
          }
        }
        """)

        #expect(usage.windows.map(\.kind) == [.session])
        #expect(usage.window(.session)?.usedPercent == 11)
    }

    @Test
    func legacyPayloadWithoutDurationsReadsWindowsByPosition() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "planType": "plus",
            "primary": { "usedPercent": 12, "resetsAt": 2000000000 },
            "secondary": { "usedPercent": 34 }
          }
        }
        """)

        #expect(usage.windows == [
            UsageWindow(
                kind: .session,
                usedPercent: 12,
                resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
                durationMinutes: nil
            ),
            UsageWindow(kind: .weekly, usedPercent: 34, resetsAt: nil, durationMinutes: nil),
        ])
    }

    @Test
    func legacyPrimaryOnlyIsTheSessionWindow() throws {
        let usage = try usage(fromAppServerJSON: """
        { "rateLimits": { "primary": { "usedPercent": 12 } } }
        """)

        #expect(usage.windows == [
            UsageWindow(kind: .session, usedPercent: 12, resetsAt: nil, durationMinutes: nil),
        ])
    }

    @Test
    func legacySecondaryOnlyIsTheWeeklyWindow() throws {
        let usage = try usage(fromAppServerJSON: """
        { "rateLimits": { "secondary": { "usedPercent": 34 } } }
        """)

        #expect(usage.windows == [
            UsageWindow(kind: .weekly, usedPercent: 34, resetsAt: nil, durationMinutes: nil),
        ])
    }

    @Test
    func windowWithoutDurationIsDroppedWhenTheOtherWindowHasOne() throws {
        let primaryUnknown = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "primary": { "usedPercent": 12 },
            "secondary": { "usedPercent": 34, "windowDurationMins": 10080 }
          }
        }
        """)
        let secondaryUnknown = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "primary": { "usedPercent": 12, "windowDurationMins": 300 },
            "secondary": { "usedPercent": 34 }
          }
        }
        """)

        #expect(primaryUnknown.windows.map(\.kind) == [.weekly])
        #expect(primaryUnknown.window(.weekly)?.usedPercent == 34)
        #expect(secondaryUnknown.windows.map(\.kind) == [.session])
        #expect(secondaryUnknown.window(.session)?.usedPercent == 12)
    }

    @Test
    func windowMissingUsedPercentIsSkippedByTheParser() throws {
        let usage = try usage(fromAppServerJSON: """
        {
          "rateLimits": {
            "primary": { "resetsAt": 2000000000, "windowDurationMins": 300 },
            "secondary": { "usedPercent": 34, "windowDurationMins": 10080 }
          }
        }
        """)

        #expect(usage.windows.map(\.kind) == [.weekly])
    }

    @Test
    func displayedUsedPercentIsZeroOnceTheResetTimeHasPassed() {
        let window = UsageWindow(
            kind: .session,
            usedPercent: 100,
            resetsAt: Date(timeIntervalSince1970: 2_000),
            durationMinutes: 300
        )

        #expect(window.displayedUsedPercent(at: Date(timeIntervalSince1970: 1_999)) == 100)
        #expect(window.displayedUsedPercent(at: Date(timeIntervalSince1970: 2_000)) == 0)
        #expect(window.displayedUsedPercent(at: Date(timeIntervalSince1970: 3_000)) == 0)
    }

    @Test
    func displayedUsedPercentKeepsUsageWhenResetTimeIsUnknown() {
        let window = UsageWindow(kind: .weekly, usedPercent: 34, resetsAt: nil, durationMinutes: nil)

        #expect(window.displayedUsedPercent(at: .distantFuture) == 34)
    }

    @Test
    func snapshotTurnsStaleOnlyAfterTheStalenessInterval() {
        let snapshot = UsageSnapshot(
            provider: .claude,
            planName: nil,
            windows: [],
            fetchedAt: Date(timeIntervalSince1970: 10_000)
        )

        #expect(snapshot.freshness(at: Date(timeIntervalSince1970: 10_000), staleAfter: 3_600) == .fresh)
        #expect(snapshot.freshness(at: Date(timeIntervalSince1970: 13_600), staleAfter: 3_600) == .fresh)
        #expect(snapshot.freshness(at: Date(timeIntervalSince1970: 13_601), staleAfter: 3_600) == .stale)
    }

    private func usage(fromAppServerJSON json: String) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: Data(json.utf8))
        let appServerRateLimits = try #require(CodexAppServerRateLimitParser().parse(response, fetchedAt: fetchedAt))
        return CodexPillAccountStatusMapper().usage(from: appServerRateLimits)
    }
}
