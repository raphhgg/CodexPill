import Foundation

enum AccountAvailabilityTarget: Hashable {
    case local
    case remote(hostDestination: String)
}

enum AccountAvailabilityStatus: Equatable {
    case availableNow
    case blocked(until: Date?, reason: AccountAvailabilityBlockingReason)
    case unavailable(reason: AccountAvailabilityUnavailableReason)
}

enum AccountAvailabilityBlockingReason: Equatable {
    case session
    case weekly
    case sessionAndWeekly
    case unknown
}

enum AccountAvailabilityUnavailableReason: Equatable {
    case disconnected
    case syncing
    case unverified
    case verificationFailed
    case missingAccount
}

struct RemoteAccountTargetContext: Equatable {
    let hostDestination: String
    let connectionState: RemoteAccountTargetConnectionState
    let verificationState: RemoteAccountTargetVerificationState
    let activeAccount: CodexAccount?
    let displayAccount: CodexAccount?
}

enum RemoteAccountTargetConnectionState: Equatable {
    case connected
    case disconnected
    case syncing
}

enum RemoteAccountTargetVerificationState: Equatable {
    case unverified
    case verifying
    case verified
    case failed
}

struct AccountTargetAvailability: Equatable {
    let target: AccountAvailabilityTarget
    let status: AccountAvailabilityStatus
    let sessionUsedPercent: Int
    let weeklyUsedPercent: Int
    let sessionResetAt: Date?
    let weeklyResetAt: Date?
}

struct AccountAvailabilitySnapshot: Equatable {
    let account: CodexAccount
    let localAvailability: AccountTargetAvailability
    let remoteAvailabilities: [AccountTargetAvailability]

    var targetAvailabilities: [AccountTargetAvailability] {
        [localAvailability] + remoteAvailabilities
    }

    func availability(for target: AccountAvailabilityTarget) -> AccountTargetAvailability? {
        switch target {
        case .local:
            return localAvailability
        case .remote:
            return remoteAvailabilities.first { $0.target == target }
        }
    }
}

struct ActiveAccountAvailabilityContext: Equatable {
    let target: AccountAvailabilityTarget
    let accountID: UUID
}

struct AccountAvailabilityService {
    func availability(
        for account: CodexAccount,
        on target: AccountAvailabilityTarget = .local,
        now: Date = .now
    ) -> AccountTargetAvailability {
        let rateLimits = account.rateLimits
        let sessionWindow = rateLimits?.sessionWindow
        let weeklyWindow = rateLimits?.weeklyWindow
        let sessionUsedPercent = sessionWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent(for: rateLimits)
        let weeklyUsedPercent = weeklyWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent(for: rateLimits)
        let sessionResetAt = sessionWindow?.resetsAt
        let weeklyResetAt = weeklyWindow?.resetsAt

        let status: AccountAvailabilityStatus
        switch (sessionUsedPercent >= 100, weeklyUsedPercent >= 100) {
        case (false, false):
            status = .availableNow
        case (true, false):
            status = .blocked(until: sessionResetAt, reason: .session)
        case (false, true):
            status = .blocked(until: weeklyResetAt, reason: .weekly)
        case (true, true):
            status = .blocked(
                until: earliestMeaningfulDate(sessionResetAt, weeklyResetAt),
                reason: .sessionAndWeekly
            )
        }

        return AccountTargetAvailability(
            target: target,
            status: status,
            sessionUsedPercent: sessionUsedPercent,
            weeklyUsedPercent: weeklyUsedPercent,
            sessionResetAt: sessionResetAt,
            weeklyResetAt: weeklyResetAt
        )
    }

    func availability(
        for remoteTarget: RemoteAccountTargetContext,
        now: Date = .now
    ) -> AccountTargetAvailability {
        let target = AccountAvailabilityTarget.remote(hostDestination: remoteTarget.hostDestination)
        let displayAccount = remoteTarget.displayAccount
        let rateLimits = displayAccount?.rateLimits
        let sessionUsedPercent = rateLimits?.sessionWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent(for: rateLimits)
        let weeklyUsedPercent = rateLimits?.weeklyWindow?.displayedUsedPercent(at: now) ?? missingWindowUsedPercent(for: rateLimits)
        let sessionResetAt = rateLimits?.sessionWindow?.resetsAt
        let weeklyResetAt = rateLimits?.weeklyWindow?.resetsAt

        let status: AccountAvailabilityStatus
        switch remoteTarget.connectionState {
        case .disconnected:
            status = .unavailable(reason: .disconnected)
        case .syncing:
            status = .unavailable(reason: .syncing)
        case .connected:
            if let activeAccount = remoteTarget.activeAccount {
                return availability(for: activeAccount, on: target, now: now)
            }

            switch remoteTarget.verificationState {
            case .verifying:
                status = .unavailable(reason: .syncing)
            case .unverified:
                status = .unavailable(reason: .unverified)
            case .failed:
                status = .unavailable(reason: .verificationFailed)
            case .verified:
                status = .unavailable(reason: displayAccount == nil ? .missingAccount : .unverified)
            }
        }

        return AccountTargetAvailability(
            target: target,
            status: status,
            sessionUsedPercent: sessionUsedPercent,
            weeklyUsedPercent: weeklyUsedPercent,
            sessionResetAt: sessionResetAt,
            weeklyResetAt: weeklyResetAt
        )
    }

    func snapshot(
        for account: CodexAccount,
        remoteTargets: [RemoteAccountTargetContext] = [],
        now: Date = .now
    ) -> AccountAvailabilitySnapshot {
        AccountAvailabilitySnapshot(
            account: account,
            localAvailability: availability(for: account, on: .local, now: now),
            remoteAvailabilities: remoteTargets.map { availability(for: $0, now: now) }
        )
    }

    private func earliestMeaningfulDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return min(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func missingWindowUsedPercent(for rateLimits: CodexRateLimitSnapshot?) -> Int {
        rateLimits == nil ? 100 : 0
    }
}
