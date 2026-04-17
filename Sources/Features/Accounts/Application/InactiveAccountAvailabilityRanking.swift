import Foundation

struct InactiveAccountAvailabilityRanking {
    func sort(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts.sorted(by: compare)
    }

    func compare(_ lhs: CodexAccount, _ rhs: CodexAccount) -> Bool {
        let leftKey = availabilitySortKey(for: lhs)
        let rightKey = availabilitySortKey(for: rhs)

        if leftKey.weeklyConstraintRank != rightKey.weeklyConstraintRank {
            return leftKey.weeklyConstraintRank < rightKey.weeklyConstraintRank
        }

        if leftKey.sessionReadyRank != rightKey.sessionReadyRank {
            return leftKey.sessionReadyRank < rightKey.sessionReadyRank
        }

        if leftKey.effectiveAvailableAt != rightKey.effectiveAvailableAt {
            return leftKey.effectiveAvailableAt < rightKey.effectiveAvailableAt
        }

        if leftKey.weeklyUsedPercent != rightKey.weeklyUsedPercent {
            return leftKey.weeklyUsedPercent < rightKey.weeklyUsedPercent
        }

        if leftKey.sessionUsedPercent != rightKey.sessionUsedPercent {
            return leftKey.sessionUsedPercent < rightKey.sessionUsedPercent
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func availabilitySortKey(for account: CodexAccount) -> AvailabilitySortKey {
        let now = Date()
        let sessionWindow = account.rateLimits?.primary
        let weeklyWindow = account.rateLimits?.secondary
        let sessionUsedPercent = sessionWindow?.displayedUsedPercent(at: now) ?? 100
        let weeklyUsedPercent = weeklyWindow?.displayedUsedPercent(at: now) ?? 100

        let weeklyConstraintRank: Int
        switch weeklyUsedPercent {
        case ..<85:
            weeklyConstraintRank = 0
        case 85..<95:
            weeklyConstraintRank = 1
        default:
            weeklyConstraintRank = 2
        }

        let sessionReadyRank: Int
        switch sessionUsedPercent {
        case ..<10:
            sessionReadyRank = 0
        case 10..<40:
            sessionReadyRank = 1
        default:
            sessionReadyRank = 2
        }

        let sessionAvailableAt: Date = sessionReadyRank == 0 ? now : (sessionWindow?.resetsAt ?? .distantFuture)
        let weeklyAvailableAt: Date = weeklyConstraintRank < 2 ? now : (weeklyWindow?.resetsAt ?? .distantFuture)

        return AvailabilitySortKey(
            weeklyConstraintRank: weeklyConstraintRank,
            sessionReadyRank: sessionReadyRank,
            effectiveAvailableAt: max(sessionAvailableAt, weeklyAvailableAt),
            weeklyUsedPercent: weeklyUsedPercent,
            sessionUsedPercent: sessionUsedPercent
        )
    }
}

private struct AvailabilitySortKey {
    let weeklyConstraintRank: Int
    let sessionReadyRank: Int
    let effectiveAvailableAt: Date
    let weeklyUsedPercent: Int
    let sessionUsedPercent: Int
}
