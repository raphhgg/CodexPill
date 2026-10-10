import Foundation

/// Session and weekly usage of one saved account, as the inactive-account ranking reads it.
struct AccountTargetAvailability: Equatable {
    let sessionUsedPercent: Int
    let weeklyUsedPercent: Int
    let sessionResetAt: Date?
    let weeklyResetAt: Date?
}

struct AccountAvailabilityService {
    func availability(for account: CodexAccount, now: Date = .now) -> AccountTargetAvailability {
        let usage = account.usage
        // An account that was never read counts as used up, so it sorts last.
        let missingWindowUsedPercent = usage == nil ? 100 : 0
        let sessionWindow = usage?.window(.session)
        let weeklyWindow = usage?.window(.weekly)
        return AccountTargetAvailability(
            sessionUsedPercent: sessionWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent,
            weeklyUsedPercent: weeklyWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent,
            sessionResetAt: sessionWindow?.resetsAt,
            weeklyResetAt: weeklyWindow?.resetsAt
        )
    }
}
