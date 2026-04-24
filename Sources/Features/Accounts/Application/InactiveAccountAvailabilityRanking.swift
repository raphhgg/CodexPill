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

struct AccountAvailabilityNotificationSettings: Equatable {
    var whenBlockedEnabled: Bool
    var whenOutEnabled: Bool
    var minimumRemainingPercent: Int
    var betterAccountWaitWindow: TimeInterval

    init(
        whenBlockedEnabled: Bool = false,
        whenOutEnabled: Bool = false,
        minimumRemainingPercent: Int = 10,
        betterAccountWaitWindow: TimeInterval = 20 * 60
    ) {
        self.whenBlockedEnabled = whenBlockedEnabled
        self.whenOutEnabled = whenOutEnabled
        self.minimumRemainingPercent = minimumRemainingPercent
        self.betterAccountWaitWindow = betterAccountWaitWindow
    }
}

enum AccountAvailabilityNotificationReason: Equatable {
    case whenBlocked
    case whenOut
}

enum AccountAvailabilityNotificationActionSuggestion: Equatable {
    case local
    case remote(hostDestination: String)
}

struct AccountAvailabilityNotificationDecision: Equatable {
    let shouldNotify: Bool
    let account: CodexAccount
    let reason: AccountAvailabilityNotificationReason
    let window: AccountAvailabilityNotificationWindow
    let waitUntil: Date?
    let suggestedActions: [AccountAvailabilityNotificationActionSuggestion]
    let triggerContext: AccountAvailabilityNotificationTriggerContext?
}

struct AccountAvailabilityNotificationTriggerContext: Equatable {
    let accountID: UUID
    let accountName: String
    let target: AccountAvailabilityTarget
    let sessionRemainingPercent: Int
    let weeklyRemainingPercent: Int
}

enum AccountAvailabilityNotificationRequestedTarget: Equatable {
    case local
    case remote(preferredHostDestination: String?)
    case bestOption
}

enum AccountAvailabilityNotificationResolvedTarget: Equatable {
    case local
    case remote(hostDestination: String)
}

struct AccountAvailabilityNotificationActionResolution: Equatable {
    let account: CodexAccount
    let target: AccountAvailabilityNotificationResolvedTarget
    let substitutionMessage: String?
}

struct AccountAvailabilityNotificationWindow: Equatable {
    let sessionResetAt: Date?
    let weeklyResetAt: Date?
}

@MainActor
final class NotificationStateStore {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var whenBlockedEnabled: Bool {
        get { settings.notificationsWhenBlockedEnabled }
        set { settings.notificationsWhenBlockedEnabled = newValue }
    }

    var whenOutEnabled: Bool {
        get { settings.notificationsWhenOutEnabled }
        set { settings.notificationsWhenOutEnabled = newValue }
    }

    func shouldDeliverNotification(
        for accountID: UUID,
        reason: AccountAvailabilityNotificationReason,
        window: AccountAvailabilityNotificationWindow
    ) -> Bool {
        guard isEnabled(for: reason) else { return false }
        guard let persistedState = settings.accountNotificationState(for: accountID) else {
            return true
        }

        return persistedState.isArmed
    }

    func recordNotification(
        for accountID: UUID,
        reason: AccountAvailabilityNotificationReason,
        window: AccountAvailabilityNotificationWindow,
        notifiedAt: Date = .now
    ) {
        settings.updateAccountNotificationState(for: accountID) { state in
            state.isArmed = false
            state.lastNotification = PersistedAccountNotificationRecord(
                reason: persistableReason(reason),
                window: persistableWindow(window),
                notifiedAt: notifiedAt
            )
        }
    }

    func markAccountActivated(_ accountID: UUID) {
        settings.updateAccountNotificationState(for: accountID) { state in
            state.isArmed = true
            state.lastNotification = nil
        }
    }

    func state(for accountID: UUID) -> PersistedAccountNotificationState? {
        settings.accountNotificationState(for: accountID)
    }

    private func isEnabled(for reason: AccountAvailabilityNotificationReason) -> Bool {
        switch reason {
        case .whenBlocked:
            whenBlockedEnabled
        case .whenOut:
            whenOutEnabled
        }
    }

    private func persistableReason(_ reason: AccountAvailabilityNotificationReason) -> PersistedAccountNotificationReason {
        switch reason {
        case .whenBlocked:
            .whenBlocked
        case .whenOut:
            .whenOut
        }
    }

    private func persistableWindow(_ window: AccountAvailabilityNotificationWindow) -> PersistedAccountNotificationWindow {
        PersistedAccountNotificationWindow(
            sessionResetAt: window.sessionResetAt,
            weeklyResetAt: window.weeklyResetAt
        )
    }
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

struct AccountAvailabilityNotificationPolicy {
    private let ranking = InactiveAccountAvailabilityRanking()

    func decision(
        previousSnapshots: [AccountAvailabilitySnapshot],
        currentSnapshots: [AccountAvailabilitySnapshot],
        activeAccounts: [ActiveAccountAvailabilityContext],
        settings: AccountAvailabilityNotificationSettings,
        now: Date = .now
    ) -> AccountAvailabilityNotificationDecision? {
        guard settings.whenBlockedEnabled || settings.whenOutEnabled else {
            return nil
        }

        let currentCandidates = notificationCandidates(
            from: currentSnapshots,
            minimumRemainingPercent: settings.minimumRemainingPercent,
            now: now
        )
        let previousCandidateIDs = Set(
            notificationCandidates(
                from: previousSnapshots,
                minimumRemainingPercent: settings.minimumRemainingPercent,
                now: now
            ).map(\.snapshot.account.id)
        )

        if settings.whenBlockedEnabled,
           hadNoNotificationWorthyAccounts(
               in: previousSnapshots,
               minimumRemainingPercent: settings.minimumRemainingPercent,
               now: now
           ),
           let bestCurrent = bestCandidate(from: currentCandidates, now: now) {
            let actions = suggestedActions(
                for: bestCurrent.snapshot,
                activeAccounts: activeAccounts,
                currentSnapshots: currentSnapshots,
                minimumRemainingPercent: settings.minimumRemainingPercent,
                now: now
            )
            if let waitDecision = waitDecision(
                currentBest: bestCurrent,
                among: currentSnapshots,
                reason: .whenBlocked,
                actions: actions,
                settings: settings,
                now: now
            ) {
                return waitDecision
            }

            return AccountAvailabilityNotificationDecision(
                shouldNotify: true,
                account: bestCurrent.snapshot.account,
                reason: .whenBlocked,
                window: notificationWindow(for: bestCurrent.availability),
                waitUntil: nil,
                suggestedActions: actions,
                triggerContext: nil
            )
        }

        guard settings.whenOutEnabled else {
            return nil
        }

        let outActiveTargets = outActiveAccounts(
            activeAccounts: activeAccounts,
            snapshots: currentSnapshots,
            now: now
        )
        guard !outActiveTargets.isEmpty else {
            return nil
        }

        let newlyOutActiveTargets = newlyOutActiveAccounts(
            activeAccounts: activeAccounts,
            previousSnapshots: previousSnapshots,
            currentSnapshots: currentSnapshots,
            now: now
        )
        let triggerContext = whenOutTriggerContext(
            from: newlyOutActiveTargets.isEmpty ? outActiveTargets : newlyOutActiveTargets,
            snapshots: currentSnapshots
        )

        let alternativeCandidates = currentCandidates.filter { candidate in
            !outActiveTargets.contains { $0.accountID == candidate.snapshot.account.id }
        }
        guard let bestAlternative = bestCandidate(from: alternativeCandidates, now: now),
              (
                !previousCandidateIDs.contains(bestAlternative.snapshot.account.id) ||
                !newlyOutActiveTargets.isEmpty
              ) else {
            return nil
        }

        let actions = suggestedActions(
            for: bestAlternative.snapshot,
            activeAccounts: activeAccounts,
            currentSnapshots: currentSnapshots,
            minimumRemainingPercent: settings.minimumRemainingPercent,
            now: now
        )
        if let waitDecision = waitDecision(
            currentBest: bestAlternative,
            among: currentSnapshots,
            reason: .whenOut,
            actions: actions,
            settings: settings,
            now: now
        ) {
            return waitDecision
        }

        return AccountAvailabilityNotificationDecision(
            shouldNotify: true,
            account: bestAlternative.snapshot.account,
            reason: .whenOut,
            window: notificationWindow(for: bestAlternative.availability),
            waitUntil: nil,
            suggestedActions: actions,
            triggerContext: triggerContext
        )
    }

    func bestNotificationWorthyAccount(
        in snapshots: [AccountAvailabilitySnapshot],
        settings: AccountAvailabilityNotificationSettings,
        now: Date = .now
    ) -> AccountAvailabilitySnapshot? {
        bestCandidate(
            from: notificationCandidates(
                from: snapshots,
                minimumRemainingPercent: settings.minimumRemainingPercent,
                now: now
            ),
            now: now
        )?.snapshot
    }

    func suggestedActions(
        for snapshot: AccountAvailabilitySnapshot,
        activeAccounts: [ActiveAccountAvailabilityContext],
        currentSnapshots: [AccountAvailabilitySnapshot],
        settings: AccountAvailabilityNotificationSettings,
        now: Date = .now
    ) -> [AccountAvailabilityNotificationActionSuggestion] {
        suggestedActions(
            for: snapshot,
            activeAccounts: activeAccounts,
            currentSnapshots: currentSnapshots,
            minimumRemainingPercent: settings.minimumRemainingPercent,
            now: now
        )
    }

    private func hadNoNotificationWorthyAccounts(
        in snapshots: [AccountAvailabilitySnapshot],
        minimumRemainingPercent: Int,
        now: Date
    ) -> Bool {
        notificationCandidates(from: snapshots, minimumRemainingPercent: minimumRemainingPercent, now: now).isEmpty
    }

    private func notificationCandidates(
        from snapshots: [AccountAvailabilitySnapshot],
        minimumRemainingPercent: Int,
        now: Date
    ) -> [NotificationCandidate] {
        snapshots.compactMap { snapshot in
            guard let availability = bestNotificationAvailability(
                in: snapshot,
                minimumRemainingPercent: minimumRemainingPercent,
                now: now
            ) else {
                return nil
            }

            return NotificationCandidate(snapshot: snapshot, availability: availability, availableAt: nil)
        }
    }

    private func bestCandidate(
        from candidates: [NotificationCandidate],
        now: Date
    ) -> NotificationCandidate? {
        candidates.min { lhs, rhs in
            if ranking.compare(lhs.availability, rhs.availability, now: now) {
                return true
            }
            if ranking.compare(rhs.availability, lhs.availability, now: now) {
                return false
            }
            return lhs.snapshot.account.name.localizedCaseInsensitiveCompare(rhs.snapshot.account.name) == .orderedAscending
        }
    }

    private func bestNotificationAvailability(
        in snapshot: AccountAvailabilitySnapshot,
        minimumRemainingPercent: Int,
        now: Date
    ) -> AccountTargetAvailability? {
        snapshot.targetAvailabilities
            .filter { isNotificationWorthy($0, minimumRemainingPercent: minimumRemainingPercent, at: now) }
            .min { lhs, rhs in
                if ranking.compare(lhs, rhs, now: now) {
                    return true
                }
                if ranking.compare(rhs, lhs, now: now) {
                    return false
                }
                return stableTargetOrdering(lhs.target) < stableTargetOrdering(rhs.target)
            }
    }

    private func outActiveAccounts(
        activeAccounts: [ActiveAccountAvailabilityContext],
        snapshots: [AccountAvailabilitySnapshot],
        now: Date
    ) -> [ActiveAccountAvailabilityContext] {
        activeAccounts.filter { active in
            guard let snapshot = snapshots.first(where: { $0.account.id == active.accountID }),
                  let availability = snapshot.availability(for: active.target) else {
                return false
            }
            return isOutOfCapacity(availability, at: now)
        }
    }

    private func newlyOutActiveAccounts(
        activeAccounts: [ActiveAccountAvailabilityContext],
        previousSnapshots: [AccountAvailabilitySnapshot],
        currentSnapshots: [AccountAvailabilitySnapshot],
        now: Date
    ) -> [ActiveAccountAvailabilityContext] {
        activeAccounts.filter { active in
            guard let currentSnapshot = currentSnapshots.first(where: { $0.account.id == active.accountID }),
                  let currentAvailability = currentSnapshot.availability(for: active.target) else {
                return false
            }

            let isCurrentlyOut = isOutOfCapacity(currentAvailability, at: now)
            guard isCurrentlyOut else {
                return false
            }

            guard let previousSnapshot = previousSnapshots.first(where: { $0.account.id == active.accountID }),
                  let previousAvailability = previousSnapshot.availability(for: active.target) else {
                return true
            }

            return !isOutOfCapacity(previousAvailability, at: now)
        }
    }

    private func isNotificationWorthy(
        _ availability: AccountTargetAvailability,
        minimumRemainingPercent: Int,
        at now: Date
    ) -> Bool {
        guard projectedStatus(of: availability, at: now) == .availableNow else {
            return false
        }

        let sessionRemaining = max(0, 100 - projectedUsedPercent(for: availability.sessionUsedPercent, resetAt: availability.sessionResetAt, at: now))
        let weeklyRemaining = max(0, 100 - projectedUsedPercent(for: availability.weeklyUsedPercent, resetAt: availability.weeklyResetAt, at: now))

        return sessionRemaining >= minimumRemainingPercent && weeklyRemaining >= minimumRemainingPercent
    }

    private func isOutOfCapacity(
        _ availability: AccountTargetAvailability,
        at now: Date
    ) -> Bool {
        switch projectedStatus(of: availability, at: now) {
        case .blocked:
            return true
        case .availableNow, .unavailable:
            return false
        }
    }

    private func waitDecision(
        currentBest: NotificationCandidate,
        among snapshots: [AccountAvailabilitySnapshot],
        reason: AccountAvailabilityNotificationReason,
        actions: [AccountAvailabilityNotificationActionSuggestion],
        settings: AccountAvailabilityNotificationSettings,
        now: Date
    ) -> AccountAvailabilityNotificationDecision? {
        let horizon = now.addingTimeInterval(settings.betterAccountWaitWindow)

        let betterFutureCandidates = snapshots.compactMap { snapshot -> NotificationCandidate? in
            let futureAvailability = earliestFutureNotificationAvailability(
                in: snapshot,
                minimumRemainingPercent: settings.minimumRemainingPercent,
                horizon: horizon,
                now: now
            )
            guard let futureAvailability else {
                return nil
            }

            if snapshot.account.id == currentBest.snapshot.account.id {
                return nil
            }

            let availableAt = ranking.sortKey(for: futureAvailability.sourceAvailability, now: now).effectiveAvailableAt
            return NotificationCandidate(
                snapshot: snapshot,
                availability: futureAvailability.projectedAvailability,
                availableAt: availableAt
            )
        }

        guard let betterFuture = bestCandidate(from: betterFutureCandidates, now: now),
              ranking.compare(betterFuture.availability, currentBest.availability, now: now),
              let waitUntil = betterFuture.availableAt,
              waitUntil <= horizon else {
            return nil
        }

        return AccountAvailabilityNotificationDecision(
            shouldNotify: false,
            account: betterFuture.snapshot.account,
            reason: reason,
            window: notificationWindow(for: betterFuture.availability),
            waitUntil: waitUntil,
            suggestedActions: actions,
            triggerContext: nil
        )
    }

    private func whenOutTriggerContext(
        from activeAccounts: [ActiveAccountAvailabilityContext],
        snapshots: [AccountAvailabilitySnapshot]
    ) -> AccountAvailabilityNotificationTriggerContext? {
        activeAccounts
            .compactMap { active -> AccountAvailabilityNotificationTriggerContext? in
                guard let snapshot = snapshots.first(where: { $0.account.id == active.accountID }),
                      let availability = snapshot.availability(for: active.target) else {
                    return nil
                }

                return AccountAvailabilityNotificationTriggerContext(
                    accountID: snapshot.account.id,
                    accountName: snapshot.account.name,
                    target: active.target,
                    sessionRemainingPercent: max(0, 100 - availability.sessionUsedPercent),
                    weeklyRemainingPercent: max(0, 100 - availability.weeklyUsedPercent)
                )
            }
            .min { lhs, rhs in
                let lhsRemaining = min(lhs.sessionRemainingPercent, lhs.weeklyRemainingPercent)
                let rhsRemaining = min(rhs.sessionRemainingPercent, rhs.weeklyRemainingPercent)
                if lhsRemaining != rhsRemaining {
                    return lhsRemaining < rhsRemaining
                }
                if lhs.accountName != rhs.accountName {
                    return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
                }
                return stableTargetOrdering(lhs.target) < stableTargetOrdering(rhs.target)
            }
    }

    private func notificationWindow(for availability: AccountTargetAvailability) -> AccountAvailabilityNotificationWindow {
        AccountAvailabilityNotificationWindow(
            sessionResetAt: availability.sessionResetAt,
            weeklyResetAt: availability.weeklyResetAt
        )
    }

    private func earliestFutureNotificationAvailability(
        in snapshot: AccountAvailabilitySnapshot,
        minimumRemainingPercent: Int,
        horizon: Date,
        now: Date
    ) -> ProjectedNotificationAvailability? {
        snapshot.targetAvailabilities
            .compactMap { availability -> ProjectedNotificationAvailability? in
                let availableAt = ranking.sortKey(for: availability, now: now).effectiveAvailableAt
                guard availableAt > now,
                      availableAt <= horizon,
                      isNotificationWorthy(availability, minimumRemainingPercent: minimumRemainingPercent, at: availableAt) else {
                    return nil
                }
                return ProjectedNotificationAvailability(
                    sourceAvailability: availability,
                    projectedAvailability: projectedAvailability(from: availability, at: availableAt)
                )
            }
            .min { lhs, rhs in
                if ranking.compare(lhs.projectedAvailability, rhs.projectedAvailability, now: now) {
                    return true
                }
                if ranking.compare(rhs.projectedAvailability, lhs.projectedAvailability, now: now) {
                    return false
                }
                return stableTargetOrdering(lhs.projectedAvailability.target) < stableTargetOrdering(rhs.projectedAvailability.target)
            }
    }

    private func projectedAvailability(from availability: AccountTargetAvailability, at date: Date) -> AccountTargetAvailability {
        AccountTargetAvailability(
            target: availability.target,
            status: projectedStatus(of: availability, at: date),
            sessionUsedPercent: projectedUsedPercent(for: availability.sessionUsedPercent, resetAt: availability.sessionResetAt, at: date),
            weeklyUsedPercent: projectedUsedPercent(for: availability.weeklyUsedPercent, resetAt: availability.weeklyResetAt, at: date),
            sessionResetAt: availability.sessionResetAt,
            weeklyResetAt: availability.weeklyResetAt
        )
    }

    private func projectedStatus(of availability: AccountTargetAvailability, at date: Date) -> AccountAvailabilityStatus {
        switch availability.status {
        case .unavailable(let reason):
            return .unavailable(reason: reason)
        case .availableNow, .blocked:
            let sessionUsedPercent = projectedUsedPercent(
                for: availability.sessionUsedPercent,
                resetAt: availability.sessionResetAt,
                at: date
            )
            let weeklyUsedPercent = projectedUsedPercent(
                for: availability.weeklyUsedPercent,
                resetAt: availability.weeklyResetAt,
                at: date
            )

            switch (sessionUsedPercent >= 100, weeklyUsedPercent >= 100) {
            case (false, false):
                return .availableNow
            case (true, false):
                return .blocked(until: availability.sessionResetAt, reason: .session)
            case (false, true):
                return .blocked(until: availability.weeklyResetAt, reason: .weekly)
            case (true, true):
                return .blocked(until: max(availability.sessionResetAt ?? .distantPast, availability.weeklyResetAt ?? .distantPast), reason: .sessionAndWeekly)
            }
        }
    }

    private func projectedUsedPercent(for currentValue: Int, resetAt: Date?, at date: Date) -> Int {
        guard let resetAt else { return currentValue }
        return resetAt <= date ? 0 : currentValue
    }

    private func suggestedActions(
        for chosenSnapshot: AccountAvailabilitySnapshot,
        activeAccounts: [ActiveAccountAvailabilityContext],
        currentSnapshots: [AccountAvailabilitySnapshot],
        minimumRemainingPercent: Int,
        now: Date
    ) -> [AccountAvailabilityNotificationActionSuggestion] {
        var actions: [AccountAvailabilityNotificationActionSuggestion] = []

        if let localActive = activeAccounts.first(where: { $0.target == .local }),
           let localSnapshot = currentSnapshots.first(where: { $0.account.id == localActive.accountID }),
           let localAvailability = localSnapshot.availability(for: .local),
           isOutOfCapacity(localAvailability, at: now) {
            actions.append(.local)
        }

        let blockedRemoteContexts = activeAccounts.compactMap { active -> String? in
            guard case .remote(let hostDestination) = active.target,
                  let snapshot = currentSnapshots.first(where: { $0.account.id == active.accountID }),
                  let availability = snapshot.availability(for: active.target),
                  isOutOfCapacity(availability, at: now) else {
                return nil
            }
            return hostDestination
        }

        if let bestRemoteHost = blockedRemoteContexts.sorted().first {
            actions.append(.remote(hostDestination: bestRemoteHost))
        }

        return actions
    }

    private func stableTargetOrdering(_ target: AccountAvailabilityTarget) -> String {
        switch target {
        case .local:
            return "local"
        case .remote(let hostDestination):
            return hostDestination
        }
    }
}

struct AccountAvailabilityNotificationActionResolver {
    private let policy = AccountAvailabilityNotificationPolicy()

    func resolve(
        notifiedAccountID: UUID,
        requestedTarget: AccountAvailabilityNotificationRequestedTarget,
        currentSnapshots: [AccountAvailabilitySnapshot],
        activeAccounts: [ActiveAccountAvailabilityContext],
        settings: AccountAvailabilityNotificationSettings,
        now: Date = .now
    ) -> AccountAvailabilityNotificationActionResolution? {
        guard let bestAccount = policy.bestNotificationWorthyAccount(
            in: currentSnapshots,
            settings: settings,
            now: now
        ) else {
            return nil
        }

        let suggestedActions = policy.suggestedActions(
            for: bestAccount,
            activeAccounts: activeAccounts,
            currentSnapshots: currentSnapshots,
            settings: settings,
            now: now
        )
        guard let resolvedTarget = resolveTarget(
            requestedTarget: requestedTarget,
            suggestedActions: suggestedActions
        ) else {
            return nil
        }

        let substitutionMessage: String?
        if bestAccount.account.id == notifiedAccountID {
            substitutionMessage = nil
        } else if let originalAccount = currentSnapshots.first(where: { $0.account.id == notifiedAccountID })?.account {
            substitutionMessage = "\(originalAccount.name) is no longer the best option. Switching to \(bestAccount.account.name) instead."
        } else {
            substitutionMessage = nil
        }

        return AccountAvailabilityNotificationActionResolution(
            account: bestAccount.account,
            target: resolvedTarget,
            substitutionMessage: substitutionMessage
        )
    }

    private func resolveTarget(
        requestedTarget: AccountAvailabilityNotificationRequestedTarget,
        suggestedActions: [AccountAvailabilityNotificationActionSuggestion]
    ) -> AccountAvailabilityNotificationResolvedTarget? {
        switch requestedTarget {
        case .local:
            return .local
        case .remote(let preferredHostDestination):
            if let preferredHostDestination,
               suggestedActions.contains(.remote(hostDestination: preferredHostDestination)) {
                return .remote(hostDestination: preferredHostDestination)
            }
            guard let firstRemote = suggestedActions.first(where: {
                if case .remote = $0 { return true }
                return false
            }) else {
                return nil
            }
            if case .remote(let hostDestination) = firstRemote {
                return .remote(hostDestination: hostDestination)
            }
            return nil
        case .bestOption:
            if suggestedActions.contains(.local) {
                return .local
            }
            guard let firstRemote = suggestedActions.first(where: {
                if case .remote = $0 { return true }
                return false
            }) else {
                return nil
            }
            if case .remote(let hostDestination) = firstRemote {
                return .remote(hostDestination: hostDestination)
            }
            return nil
        }
    }
}

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

private struct NotificationCandidate {
    let snapshot: AccountAvailabilitySnapshot
    let availability: AccountTargetAvailability
    let availableAt: Date?
}

private struct ProjectedNotificationAvailability {
    let sourceAvailability: AccountTargetAvailability
    let projectedAvailability: AccountTargetAvailability
}
