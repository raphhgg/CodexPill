import Foundation

struct InactiveAccountAvailabilityRanking {
    private let availabilityService = AccountAvailabilityService()

    func sort(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts.sorted(by: compare)
    }

    func compare(_ lhs: CodexAccount, _ rhs: CodexAccount) -> Bool {
        let leftKey = sortKey(for: availabilityService.availability(for: lhs), now: .now)
        let rightKey = sortKey(for: availabilityService.availability(for: rhs), now: .now)

        if leftKey.longWindowConstraintRank != rightKey.longWindowConstraintRank {
            return leftKey.longWindowConstraintRank < rightKey.longWindowConstraintRank
        }

        if leftKey.sessionReadyRank != rightKey.sessionReadyRank {
            return leftKey.sessionReadyRank < rightKey.sessionReadyRank
        }

        if leftKey.effectiveAvailableAt != rightKey.effectiveAvailableAt {
            return leftKey.effectiveAvailableAt < rightKey.effectiveAvailableAt
        }

        if leftKey.longWindowUsedPercent != rightKey.longWindowUsedPercent {
            return leftKey.longWindowUsedPercent < rightKey.longWindowUsedPercent
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

        if leftKey.longWindowConstraintRank != rightKey.longWindowConstraintRank {
            return leftKey.longWindowConstraintRank < rightKey.longWindowConstraintRank
        }

        if leftKey.sessionReadyRank != rightKey.sessionReadyRank {
            return leftKey.sessionReadyRank < rightKey.sessionReadyRank
        }

        if leftKey.effectiveAvailableAt != rightKey.effectiveAvailableAt {
            return leftKey.effectiveAvailableAt < rightKey.effectiveAvailableAt
        }

        if leftKey.longWindowUsedPercent != rightKey.longWindowUsedPercent {
            return leftKey.longWindowUsedPercent < rightKey.longWindowUsedPercent
        }

        return leftKey.sessionUsedPercent < rightKey.sessionUsedPercent
    }

    func sortKey(for availability: AccountTargetAvailability, now: Date = .now) -> AvailabilitySortKey {
        let sessionUsedPercent = projectedUsedPercent(
            currentValue: availability.sessionUsedPercent,
            resetAt: availability.sessionResetAt,
            now: now
        )
        let longWindowUsedPercent = projectedUsedPercent(
            currentValue: availability.longWindowUsedPercent,
            resetAt: availability.longWindowResetAt,
            now: now
        )

        let longWindowConstraintRank: Int
        switch longWindowUsedPercent {
        case ..<85:
            longWindowConstraintRank = 0
        case 85..<95:
            longWindowConstraintRank = 1
        default:
            longWindowConstraintRank = 2
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
        let longWindowAvailableAt: Date = longWindowConstraintRank < 2 ? now : (availability.longWindowResetAt ?? .distantFuture)

        return AvailabilitySortKey(
            longWindowConstraintRank: longWindowConstraintRank,
            sessionReadyRank: sessionReadyRank,
            effectiveAvailableAt: max(sessionAvailableAt, longWindowAvailableAt),
            longWindowUsedPercent: longWindowUsedPercent,
            sessionUsedPercent: sessionUsedPercent
        )
    }

    private func projectedUsedPercent(currentValue: Int, resetAt: Date?, now: Date) -> Int {
        guard let resetAt else { return currentValue }
        return resetAt <= now ? 0 : currentValue
    }
}

struct AvailabilitySortKey {
    let longWindowConstraintRank: Int
    let sessionReadyRank: Int
    let effectiveAvailableAt: Date
    let longWindowUsedPercent: Int
    let sessionUsedPercent: Int
}
