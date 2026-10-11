import Foundation
import Testing

@testable import Refill

struct RetryAfterTests {
    private let now = Date(timeIntervalSince1970: 1_792_567_600) // Wed, 21 Oct 2026 07:26:40 GMT

    @Test
    func readsDelaySecondsOrAnHTTPDate() {
        #expect(RetryAfter.delay("120", now: now) == 120)
        #expect(RetryAfter.delay(" 120 ", now: now) == 120)
        #expect(RetryAfter.delay("Wed, 21 Oct 2026 07:28:00 GMT", now: now) == 80)
    }

    @Test
    func aPastDateMeansNoWait() {
        #expect(RetryAfter.delay("Wed, 21 Oct 2026 07:00:00 GMT", now: now) == 0)
    }

    @Test
    func aMissingOrUnreadableHeaderNamesNoWait() {
        #expect(RetryAfter.delay(nil, now: now) == nil)
        #expect(RetryAfter.delay("soon", now: now) == nil)
        #expect(RetryAfter.delay("-5", now: now) == nil)
    }
}
