import Foundation
import Testing

@testable import rusage

struct ClaudeUsageAPITests {
    @Test
    func readsTheFiveHourAndSevenDayWindowsOnly() throws {
        let report = try ClaudeUsageAPI.parseUsage(Data(ClaudeUsageFixture.usageResponse.utf8))

        #expect(report == ClaudeUsageReport(
            fiveHour: .init(usedPercent: 64.4, resetsAt: Date(timeIntervalSince1970: 1_791_644_400)),
            sevenDay: .init(usedPercent: 21, resetsAt: Date(timeIntervalSince1970: 1_791_968_400))
        ))
    }

    @Test
    func aMissingOrNullWindowIsAbsent() throws {
        let report = try ClaudeUsageAPI.parseUsage(Data(#"{"five_hour":null,"seven_day":{"utilization":0,"resets_at":null}}"#.utf8))

        #expect(report == ClaudeUsageReport(fiveHour: nil, sevenDay: .init(usedPercent: 0, resetsAt: nil)))
    }

    @Test
    func usageSavedBeforeModelLimitsStillReads() throws {
        let saved = try JSONDecoder().decode(ClaudeUsageReport.self, from: Data(#"{"sevenDay":{"usedPercent":21}}"#.utf8))

        #expect(saved == ClaudeUsageReport(fiveHour: nil, sevenDay: .init(usedPercent: 21, resetsAt: nil)))
    }

    @Test
    func enabledExtraUsageReadsAsMoneyFromMinorUnits() throws {
        let report = try ClaudeUsageAPI.parseUsage(Data(#"""
        {"five_hour":null,"seven_day":{"utilization":21,"resets_at":null},
         "extra_usage":{"is_enabled":true,"used_credits":1240,"monthly_limit":5000,"currency":"USD","decimal_places":2}}
        """#.utf8))

        #expect(report.extraUsage == ClaudeUsageReport.ExtraUsage(spent: Decimal(string: "12.4")!, limit: 50, currencyCode: "USD"))
    }

    @Test
    func uncappedExtraUsageWithoutACurrencyReadsAsDollars() throws {
        let report = try ClaudeUsageAPI.parseUsage(Data(#"""
        {"seven_day":{"utilization":21,"resets_at":null},
         "extra_usage":{"is_enabled":true,"used_credits":1240,"monthly_limit":null,"currency":null,"decimal_places":null}}
        """#.utf8))

        #expect(report.extraUsage == ClaudeUsageReport.ExtraUsage(spent: Decimal(string: "12.4")!, limit: nil, currencyCode: "USD"))
    }

    @Test(arguments: [
        #"{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"currency":null,"decimal_places":null,"disabled_reason":null,"user_disabled":true,"spend_limit_reached":false,"credits_ever_enabled":true,"daily":null,"weekly":null}"#,
        #"{"is_enabled":true,"used_credits":"lots","monthly_limit":5000}"#,
        #""on""#,
    ])
    func disabledOrUnreadableExtraUsageIsAbsentAndKeepsTheWindows(extraUsage: String) throws {
        let report = try ClaudeUsageAPI.parseUsage(Data(#"{"seven_day":{"utilization":21,"resets_at":null},"extra_usage":\#(extraUsage)}"#.utf8))

        #expect(report == ClaudeUsageReport(fiveHour: nil, sevenDay: .init(usedPercent: 21, resetsAt: nil)))
    }

    @Test
    func savedExtraUsageRoundTrips() throws {
        let report = ClaudeUsageReport(
            fiveHour: nil,
            sevenDay: .init(usedPercent: 21, resetsAt: nil),
            extraUsage: .init(spent: Decimal(string: "12.4")!, limit: 50, currencyCode: "EUR")
        )

        #expect(try JSONDecoder().decode(ClaudeUsageReport.self, from: JSONEncoder().encode(report)) == report)
    }

    @Test
    func theRequestCarriesTheTokenAndBetaHeaderToAnthropicOnly() throws {
        let token = try #require(ClaudeAccessToken("fake-claude-access-token"))
        let request = ClaudeUsageAPI.request(using: token)

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-claude-access-token")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test
    func redirectsStayOnTheSameHostOverHTTPS() {
        let origin = URL(string: "https://api.anthropic.com/api/oauth/usage")

        #expect(ClaudeUsageAPI.allowsRedirect(from: origin, to: URL(string: "https://api.anthropic.com/api/oauth/usage/v2")) == true)
        #expect(ClaudeUsageAPI.allowsRedirect(from: origin, to: URL(string: "https://example.com/collect")) == false)
        #expect(ClaudeUsageAPI.allowsRedirect(from: origin, to: URL(string: "https://api.anthropic.com.example.com/")) == false)
        #expect(ClaudeUsageAPI.allowsRedirect(from: origin, to: URL(string: "http://api.anthropic.com/api/oauth/usage")) == false)
        #expect(ClaudeUsageAPI.allowsRedirect(from: nil, to: URL(string: "https://api.anthropic.com/")) == false)
    }

    @Test
    func statusCodesMapToSignInAccessAndRateLimitErrors() {
        #expect(ClaudeUsageAPI.error(forStatus: 200, retryAfter: nil) == nil)
        #expect(ClaudeUsageAPI.error(forStatus: 401, retryAfter: nil) == .unauthorized)
        #expect(ClaudeUsageAPI.error(forStatus: 403, retryAfter: nil) == .forbidden)
        #expect(ClaudeUsageAPI.error(forStatus: 429, retryAfter: 120) == .rateLimited(retryAfter: 120))
        #expect(ClaudeUsageAPI.error(forStatus: 429, retryAfter: nil) == .rateLimited(retryAfter: nil))
        #expect(ClaudeUsageAPI.error(forStatus: 503, retryAfter: nil) == .httpStatus(503))
    }

    @Test
    func theProfileGivesThePlanWithItsMultiplierAndTheEmail() {
        let max = Data(#"{"account":{"uuid":"fake-uuid","email":"sam@example.com"},"organization":{"organization_type":"claude_max","rate_limit_tier":"default_claude_max_20x"}}"#.utf8)
        let pro = Data(#"{"account":{"email_address":"kim@example.com"},"organization":{"organization_type":"claude_pro","rate_limit_tier":"default_claude_pro"}}"#.utf8)
        let unknown = Data(#"{"organization":{"organization_type":"claude_free"}}"#.utf8)

        #expect(ClaudeUsageAPI.parseProfile(max) == ClaudeProfile(planName: "max_20x", email: "sam@example.com"))
        #expect(ClaudeUsageAPI.parseProfile(pro) == ClaudeProfile(planName: "pro", email: "kim@example.com"))
        #expect(ClaudeUsageAPI.parseProfile(unknown) == ClaudeProfile(planName: nil, email: nil))
        #expect(ClaudeUsageAPI.parseProfile(Data("<html>".utf8)) == nil)
    }
}
