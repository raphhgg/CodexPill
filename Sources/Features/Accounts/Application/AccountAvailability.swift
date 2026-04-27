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

    var isAvailableNow: Bool {
        if case .availableNow = status {
            return true
        }
        return false
    }

    var nextAvailableAt: Date? {
        switch status {
        case .availableNow:
            return nil
        case .blocked(let until, _):
            return until
        case .unavailable:
            return nil
        }
    }
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

    var nextAvailabilityAt: Date? {
        targetAvailabilities
            .compactMap(\.nextAvailableAt)
            .min()
    }
}

struct AccountAvailabilityTransition: Equatable {
    let target: AccountAvailabilityTarget
    let from: AccountAvailabilityStatus?
    let to: AccountAvailabilityStatus

    var becameAvailable: Bool {
        guard case .availableNow = to else { return false }
        guard let from else { return false }
        if case .availableNow = from {
            return false
        }
        return true
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
        let sessionWindow = account.rateLimits?.primary
        let weeklyWindow = account.rateLimits?.secondary
        let sessionUsedPercent = sessionWindow?.displayedUsedPercent(at: now) ?? 100
        let weeklyUsedPercent = weeklyWindow?.displayedUsedPercent(at: now) ?? 100
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
        let sessionUsedPercent = displayAccount?.rateLimits?.primary?.displayedUsedPercent(at: now) ?? 100
        let weeklyUsedPercent = displayAccount?.rateLimits?.secondary?.displayedUsedPercent(at: now) ?? 100
        let sessionResetAt = displayAccount?.rateLimits?.primary?.resetsAt
        let weeklyResetAt = displayAccount?.rateLimits?.secondary?.resetsAt

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

    func transitions(
        from previous: AccountAvailabilitySnapshot?,
        to current: AccountAvailabilitySnapshot
    ) -> [AccountAvailabilityTransition] {
        let previousStatuses = Dictionary(
            uniqueKeysWithValues: previous?.targetAvailabilities.map { ($0.target, $0.status) } ?? []
        )

        return current.targetAvailabilities.compactMap { availability in
            let transition = AccountAvailabilityTransition(
                target: availability.target,
                from: previousStatuses[availability.target],
                to: availability.status
            )
            return transition.becameAvailable ? transition : nil
        }
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
}
