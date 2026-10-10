import Foundation
import Testing

@testable import CodexPill

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
    func statusCodesMapToSignInAndRateLimitErrors() {
        #expect(ClaudeUsageAPI.error(forStatus: 200, retryAfter: nil) == nil)
        #expect(ClaudeUsageAPI.error(forStatus: 401, retryAfter: nil) == .unauthorized)
        #expect(ClaudeUsageAPI.error(forStatus: 429, retryAfter: "120") == .rateLimited(retryAfter: 120))
        #expect(ClaudeUsageAPI.error(forStatus: 429, retryAfter: nil) == .rateLimited(retryAfter: nil))
        #expect(ClaudeUsageAPI.error(forStatus: 429, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT") == .rateLimited(retryAfter: nil))
        #expect(ClaudeUsageAPI.error(forStatus: 503, retryAfter: nil) == .httpStatus(503))
    }
}
