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
        let rateLimits = account.rateLimits
        // An account that was never read counts as used up, so it sorts last.
        let missingWindowUsedPercent = rateLimits == nil ? 100 : 0
        let sessionWindow = rateLimits?.sessionWindow
        let weeklyWindow = rateLimits?.weeklyWindow
        return AccountTargetAvailability(
            sessionUsedPercent: sessionWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent,
            weeklyUsedPercent: weeklyWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent,
            sessionResetAt: sessionWindow?.resetsAt,
            weeklyResetAt: weeklyWindow?.resetsAt
        )
    }
}
