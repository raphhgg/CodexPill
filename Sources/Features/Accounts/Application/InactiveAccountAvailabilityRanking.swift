import Foundation

struct InactiveAccountAvailabilityRanking {
    private let availabilityService = AccountAvailabilityService()

    func sort(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts.sorted(by: compare)
    }

    func compare(_ lhs: CodexAccount, _ rhs: CodexAccount) -> Bool {
        let leftKey = sortKey(for: availabilityService.snapshot(for: lhs, now: .now).localAvailability, now: .now)
        let rightKey = sortKey(for: availabilityService.snapshot(for: rhs, now: .now).localAvailability, now: .now)

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

    func compare(
        _ lhs: AccountTargetAvailability,
        _ rhs: AccountTargetAvailability,
        now: Date = .now
    ) -> Bool {
        let leftKey = sortKey(for: lhs, now: now)
        let rightKey = sortKey(for: rhs, now: now)

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

        return leftKey.sessionUsedPercent < rightKey.sessionUsedPercent
    }

    func sortKey(for availability: AccountTargetAvailability, now: Date = .now) -> AvailabilitySortKey {
        let sessionUsedPercent = projectedUsedPercent(
            currentValue: availability.sessionUsedPercent,
            resetAt: availability.sessionResetAt,
            now: now
        )
        let weeklyUsedPercent = projectedUsedPercent(
            currentValue: availability.weeklyUsedPercent,
            resetAt: availability.weeklyResetAt,
            now: now
        )

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

        let sessionAvailableAt: Date = sessionReadyRank == 0 ? now : (availability.sessionResetAt ?? .distantFuture)
        let weeklyAvailableAt: Date = weeklyConstraintRank < 2 ? now : (availability.weeklyResetAt ?? .distantFuture)

        return AvailabilitySortKey(
            weeklyConstraintRank: weeklyConstraintRank,
            sessionReadyRank: sessionReadyRank,
            effectiveAvailableAt: max(sessionAvailableAt, weeklyAvailableAt),
            weeklyUsedPercent: weeklyUsedPercent,
            sessionUsedPercent: sessionUsedPercent
        )
    }

    private func projectedUsedPercent(currentValue: Int, resetAt: Date?, now: Date) -> Int {
        guard let resetAt else { return currentValue }
        return resetAt <= now ? 0 : currentValue
    }
}

struct AvailabilitySortKey {
    let weeklyConstraintRank: Int
    let sessionReadyRank: Int
    let effectiveAvailableAt: Date
    let weeklyUsedPercent: Int
    let sessionUsedPercent: Int
}
