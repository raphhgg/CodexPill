import Foundation

enum CursorUsageSummaryFixtures {
    /// Shape observed from `GET https://cursor.com/api/usage-summary` on a Pro account (2026-10-09).
    /// Every value is synthetic. Amounts are cents; percent fields are already in percent units.
    static let proPlan = Data("""
    {
      "billingCycleStart": "2026-09-30T15:23:08.000Z",
      "billingCycleEnd": "2026-10-30T15:23:08.000Z",
      "membershipType": "pro",
      "limitType": "user",
      "isUnlimited": false,
      "autoModelSelectedDisplayMessage": "Auto usage message",
      "namedModelSelectedDisplayMessage": "Named model usage message",
      "individualUsage": {
        "plan": {
          "enabled": true,
          "used": 2000,
          "limit": 2000,
          "remaining": 0,
          "breakdown": {
            "included": 2000,
            "bonus": 430,
            "total": 2430
          },
          "autoPercentUsed": 84.35,
          "apiPercentUsed": 0,
          "totalPercentUsed": 82.29
        },
        "onDemand": {
          "enabled": false,
          "used": 0,
          "limit": null,
          "remaining": null
        }
      },
      "teamUsage": {}
    }
    """.utf8)
}
