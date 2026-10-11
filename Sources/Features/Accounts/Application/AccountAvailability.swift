import Foundation

/// One saved account's usage as the inactive-account ranking reads it: the session window, and the fullest of its
/// longer windows (weekly, monthly, or any other length).
struct AccountTargetAvailability: Equatable {
    let sessionUsedPercent: Int
    let longWindowUsedPercent: Int
    let sessionResetAt: Date?
    let longWindowResetAt: Date?
}

struct AccountAvailabilityService {
    func availability(for account: CodexAccount, now: Date = .now) -> AccountTargetAvailability {
        let usage = account.usage
        // An account that was never read counts as used up, so it sorts last.
        let missingWindowUsedPercent = usage == nil ? 100 : 0
        let sessionWindow = usage?.window(.session)
        let longWindow = usage?.windows
            .filter { $0.kind != .session }
            .max { $0.displayedUsedPercent(at: now) < $1.displayedUsedPercent(at: now) }
        return AccountTargetAvailability(
            sessionUsedPercent: sessionWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent,
            longWindowUsedPercent: longWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent,
            sessionResetAt: sessionWindow?.resetsAt,
            longWindowResetAt: longWindow?.resetsAt
        )
    }
}
