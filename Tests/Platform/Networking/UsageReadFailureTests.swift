import Testing

@testable import Refill

struct UsageReadFailureTests {
    @Test(arguments: [
        (ClaudeUsageWebError.unauthorized, "unauthorized"),
        (.forbidden, "http 403"),
        (.rateLimited(retryAfter: 60), "rate limited"),
        (.httpStatus(503), "http 503"),
        (.transport, "network"),
    ])
    func eachClaudeReadErrorLogsOnlyItsCategory(error: ClaudeUsageWebError, logged: String) {
        #expect(UsageReadFailure(error).logDescription == logged)
    }

    @Test(arguments: [
        (CursorUsageWebError.unauthorized, "unauthorized"),
        (.forbidden, "http 403"),
        (.rateLimited(retryAfter: nil), "rate limited"),
        (.httpStatus(500), "http 500"),
        (.transport, "network"),
    ])
    func eachCursorReadErrorLogsOnlyItsCategory(error: CursorUsageWebError, logged: String) {
        #expect(UsageReadFailure(error).logDescription == logged)
    }
}
