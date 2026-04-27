import Foundation

struct MenuBarAccountCatalogEntry: Equatable {
    let account: CodexAccount
    let displayAccount: CodexAccount
    let placement: MenuBarAccountPlacement?

    var isActive: Bool {
        placement != nil
    }
}

struct MenuBarAccountCatalogProjection {
    private let savedAccountRelinker = SavedAccountRelinker()
    private let inactiveAccountAvailabilityRanking = InactiveAccountAvailabilityRanking()
    private let availabilityService = AccountAvailabilityService()

    let activeAccount: CodexAccount?
    let inactiveAccounts: [CodexAccount]
    let remoteHosts: [RemoteHostMenuState]

    var allSavedAccounts: [CodexAccount] {
        [activeAccount].compactMap { $0 } + inactiveAccounts
    }

    var resolvedRemoteHosts: [RemoteHostMenuState] {
        remoteHosts.map(resolveRemoteHost)
    }

    var connectedRemoteHosts: [RemoteHostMenuState] {
        resolvedRemoteHosts.filter { remoteHost in
            guard let availability = remoteTargetAvailability(for: remoteHost) else { return false }
            if case .unavailable(reason: .disconnected) = availability.status {
                return false
            }
            return remoteHost.displayAccount != nil
        }
    }

    var remoteTargetAvailabilities: [String: AccountTargetAvailability] {
        Dictionary(
            uniqueKeysWithValues: resolvedRemoteHosts.compactMap { remoteHost in
                guard let availability = remoteTargetAvailability(for: remoteHost) else { return nil }
                return (remoteHost.destination, availability)
            }
        )
    }

    var accountCatalogEntries: [MenuBarAccountCatalogEntry] {
        let remoteActiveIDs = Set(connectedRemoteHosts.compactMap(\.activeAccount?.id))

        let activeEntries = allSavedAccounts.compactMap { account -> MenuBarAccountCatalogEntry? in
            let isLocal = activeAccount?.id == account.id
            let isRemote = remoteActiveIDs.contains(account.id)
            guard isLocal || isRemote else { return nil }
            return MenuBarAccountCatalogEntry(
                account: account,
                displayAccount: effectiveDisplayAccount(for: account),
                placement: placement(isLocal: isLocal, isRemote: isRemote)
            )
        }
        .sorted(by: compareActiveEntries)

        let activeIDs = Set(activeEntries.map(\.account.id))
        let nonActiveEntries = allSavedAccounts
            .filter { !activeIDs.contains($0.id) }
            .map {
                MenuBarAccountCatalogEntry(
                    account: $0,
                    displayAccount: effectiveDisplayAccount(for: $0),
                    placement: nil
                )
            }
            .sorted(by: compareCatalogEntries)

        return activeEntries + nonActiveEntries
    }

    var availabilitySnapshots: [AccountAvailabilitySnapshot] {
        allSavedAccounts.map { account in
            availabilityService.snapshot(
                for: effectiveDisplayAccount(for: account),
                remoteTargets: resolvedRemoteHosts.compactMap { remoteHost in
                    guard remoteHost.displayAccount?.id == account.id else { return nil }
                    return RemoteAccountTargetContext(
                        hostDestination: remoteHost.destination,
                        connectionState: remoteConnectionState(for: remoteHost.connectionState),
                        verificationState: remoteVerificationState(for: remoteHost.verificationStatus),
                        activeAccount: remoteHost.activeAccount,
                        displayAccount: remoteHost.displayAccount
                    )
                }
            )
        }
    }

    private func placement(isLocal: Bool, isRemote: Bool) -> MenuBarAccountPlacement? {
        switch (isLocal, isRemote) {
        case (true, true):
            return .localAndRemote
        case (true, false):
            return .local
        case (false, true):
            return .remote
        case (false, false):
            return nil
        }
    }

    private func resolveRemoteHost(_ remoteHost: RemoteHostMenuState) -> RemoteHostMenuState {
        guard let activeAccount = remoteHost.activeAccount else {
            return remoteHost
        }

        return RemoteHostMenuState(
            name: remoteHost.name,
            destination: remoteHost.destination,
            connectionState: remoteHost.connectionState,
            desiredAccount: remoteHost.desiredAccount,
            activeAccount: resolveRemoteActiveAccount(activeAccount),
            detectedAccount: remoteHost.detectedAccount,
            verificationStatus: remoteHost.verificationStatus,
            lastVerificationError: remoteHost.lastVerificationError,
            deployedAccountIDs: remoteHost.deployedAccountIDs
        )
    }

    private func resolveRemoteActiveAccount(_ remoteAccount: CodexAccount) -> CodexAccount {
        guard let matchedAccount = savedAccountRelinker.resolveCanonicalAccount(
            for: remoteAccount,
            among: allSavedAccounts
        ) else {
            return remoteAccount
        }

        var resolvedAccount = matchedAccount
        resolvedAccount.applyRemoteMetadata(
            email: remoteAccount.email ?? matchedAccount.email,
            planType: remoteAccount.planType ?? matchedAccount.planType,
            rateLimits: RemoteRateLimitResolution().preferredRateLimits(
                remote: remoteAccount.rateLimits,
                fallback: matchedAccount.rateLimits,
                candidateAccounts: allSavedAccounts,
                baseAccount: matchedAccount,
                remoteEmail: remoteAccount.email
            )
        )
        resolvedAccount.updatedAt = max(remoteAccount.updatedAt, matchedAccount.updatedAt)
        return resolvedAccount
    }

    private func compareActiveEntries(_ lhs: MenuBarAccountCatalogEntry, _ rhs: MenuBarAccountCatalogEntry) -> Bool {
        let leftRank = placementRank(lhs.placement)
        let rightRank = placementRank(rhs.placement)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.account.name.localizedCaseInsensitiveCompare(rhs.account.name) == .orderedAscending
    }

    private func placementRank(_ placement: MenuBarAccountPlacement?) -> Int {
        switch placement {
        case .localAndRemote:
            return 0
        case .local:
            return 1
        case .remote:
            return 2
        case .none:
            return 3
        }
    }

    private func compareCatalogEntries(_ lhs: MenuBarAccountCatalogEntry, _ rhs: MenuBarAccountCatalogEntry) -> Bool {
        inactiveAccountAvailabilityRanking.compare(lhs.account, rhs.account)
    }

    private func effectiveDisplayAccount(for account: CodexAccount) -> CodexAccount {
        if activeAccount?.id == account.id {
            return account
        }
        if let remoteAccount = connectedRemoteHosts.first(where: { $0.activeAccount?.id == account.id })?.activeAccount {
            return remoteAccount
        }
        return account
    }

    private func remoteTargetAvailability(for remoteHost: RemoteHostMenuState) -> AccountTargetAvailability? {
        guard remoteHost.displayAccount != nil || remoteHost.connectionState == .disconnected else { return nil }
        return availabilityService.availability(
            for: RemoteAccountTargetContext(
                hostDestination: remoteHost.destination,
                connectionState: remoteConnectionState(for: remoteHost.connectionState),
                verificationState: remoteVerificationState(for: remoteHost.verificationStatus),
                activeAccount: remoteHost.activeAccount,
                displayAccount: remoteHost.displayAccount
            )
        )
    }

    private func remoteConnectionState(for state: RemoteHostConnectionState) -> RemoteAccountTargetConnectionState {
        switch state {
        case .connected:
            return .connected
        case .disconnected:
            return .disconnected
        case .syncing:
            return .syncing
        }
    }

    private func remoteVerificationState(for state: PersistedRemoteHostState.VerificationStatus) -> RemoteAccountTargetVerificationState {
        switch state {
        case .unverified:
            return .unverified
        case .verifying:
            return .verifying
        case .verified:
            return .verified
        case .failed:
            return .failed
        }
    }
}
