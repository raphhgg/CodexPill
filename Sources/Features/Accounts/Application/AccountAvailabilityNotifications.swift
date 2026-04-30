import Foundation

struct AccountAvailabilityNotificationSettings: Equatable {
    var whenBlockedEnabled: Bool
    var whenOutEnabled: Bool

    init(
        whenBlockedEnabled: Bool = false,
        whenOutEnabled: Bool = false
    ) {
        self.whenBlockedEnabled = whenBlockedEnabled
        self.whenOutEnabled = whenOutEnabled
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
final class AccountAvailabilityNotificationStore {
    private let preferences: NotificationPreferencesStore
    private let stateStore: NotificationStateStore

    init(
        preferences: NotificationPreferencesStore,
        stateStore: NotificationStateStore
    ) {
        self.preferences = preferences
        self.stateStore = stateStore
    }

    var whenBlockedEnabled: Bool {
        get { preferences.notificationsWhenBlockedEnabled }
        set { preferences.notificationsWhenBlockedEnabled = newValue }
    }

    var whenOutEnabled: Bool {
        get { preferences.notificationsWhenOutEnabled }
        set { preferences.notificationsWhenOutEnabled = newValue }
    }

    func shouldDeliverNotification(
        for accountID: UUID,
        reason: AccountAvailabilityNotificationReason,
        window: AccountAvailabilityNotificationWindow
    ) -> Bool {
        guard isEnabled(for: reason) else { return false }
        guard let persistedState = stateStore.accountNotificationState(for: accountID) else {
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
        stateStore.updateAccountNotificationState(for: accountID) { state in
            state.isArmed = false
            state.lastNotification = PersistedAccountNotificationRecord(
                reason: persistableReason(reason),
                window: persistableWindow(window),
                notifiedAt: notifiedAt
            )
        }
    }

    func markAccountActivated(_ accountID: UUID) {
        stateStore.updateAccountNotificationState(for: accountID) { state in
            state.isArmed = true
            state.lastNotification = nil
        }
    }

    func state(for accountID: UUID) -> PersistedAccountNotificationState? {
        stateStore.accountNotificationState(for: accountID)
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

struct AccountAvailabilityNotificationPolicy {
    private let ranking = InactiveAccountAvailabilityRanking()
    private static let minimumUsableRemainingPercent = 10

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
            minimumRemainingPercent: Self.minimumUsableRemainingPercent,
            now: now
        )
        let previousCandidateIDs = Set(
            notificationCandidates(
                from: previousSnapshots,
                minimumRemainingPercent: Self.minimumUsableRemainingPercent,
                now: now
            ).map(\.snapshot.account.id)
        )

        if settings.whenBlockedEnabled,
           hadNoNotificationWorthyAccounts(
               in: previousSnapshots,
               minimumRemainingPercent: Self.minimumUsableRemainingPercent,
               now: now
           ),
           let bestCurrent = bestCandidate(from: currentCandidates, now: now) {
            let actions = suggestedActions(
                for: bestCurrent.snapshot,
                activeAccounts: activeAccounts,
                currentSnapshots: currentSnapshots,
                minimumRemainingPercent: Self.minimumUsableRemainingPercent,
                now: now
            )

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
            minimumRemainingPercent: Self.minimumUsableRemainingPercent,
            now: now
        )

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
                minimumRemainingPercent: Self.minimumUsableRemainingPercent,
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
            minimumRemainingPercent: Self.minimumUsableRemainingPercent,
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

private struct NotificationCandidate {
    let snapshot: AccountAvailabilitySnapshot
    let availability: AccountTargetAvailability
    let availableAt: Date?
}
