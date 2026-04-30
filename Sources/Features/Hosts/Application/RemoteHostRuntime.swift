import Foundation

@MainActor
final class RemoteHostRuntime {
    private let settings: RemoteHostSettingsStore
    private let remoteHostClient: RemoteHostClient
    private let remoteHostAccountVerifier: RemoteHostAccountVerifier
    private let savedAccountRelinker: SavedAccountRelinker
    private let accounts: () -> [CodexAccount]
    private let persistAccountMetadata: (CodexAccount) -> Void
    private let markAccountActivated: (UUID) -> Void

    private var connectionStates: [String: RemoteHostConnectionState] = [:]

    init(
        settings: RemoteHostSettingsStore,
        remoteHostClient: RemoteHostClient,
        remoteHostAccountVerifier: RemoteHostAccountVerifier = RemoteHostAccountVerifier(),
        savedAccountRelinker: SavedAccountRelinker = SavedAccountRelinker(),
        accounts: @escaping () -> [CodexAccount],
        persistAccountMetadata: @escaping (CodexAccount) -> Void,
        markAccountActivated: @escaping (UUID) -> Void
    ) {
        self.settings = settings
        self.remoteHostClient = remoteHostClient
        self.remoteHostAccountVerifier = remoteHostAccountVerifier
        self.savedAccountRelinker = savedAccountRelinker
        self.accounts = accounts
        self.persistAccountMetadata = persistAccountMetadata
        self.markAccountActivated = markAccountActivated
    }

    func restorePersistedState() {
        connectionStates = [:]
        for hostState in settings.remoteHostStates {
            connectionStates[hostState.host.destination] = .disconnected
        }
    }

    func menuStates() -> [RemoteHostMenuState] {
        settings.remoteHostStates.map { hostState in
            RemoteHostMenuState(
                name: hostState.host.displayName,
                destination: hostState.host.destination,
                connectionState: connectionState(for: hostState),
                desiredAccount: desiredAccount(for: hostState),
                activeAccount: hostState.verifiedAccount,
                detectedAccount: detectedAccount(for: hostState),
                verificationStatus: hostState.verificationStatus,
                lastVerificationError: hostState.lastVerificationError,
                deployedAccountIDs: hostState.installedAccountIDs
            )
        }
    }

    func beginHostSwitch(to account: CodexAccount, on host: RemoteHost) {
        if let previousRemoteAccount = settings.remoteHostState(for: host.destination)?.verifiedAccount,
           previousRemoteAccount.id != account.id {
            persistRemoteAccountIntoCatalogIfNeeded(previousRemoteAccount)
        }
        setConnectionState(.syncing, for: host.destination)
    }

    func applySwitchOutcome(
        _ outcome: AccountsController.RemoteHostSwitchOutcome,
        account: CodexAccount,
        host: RemoteHost,
        recordsInstalledAccountOnFailure: Bool = false
    ) {
        switch outcome {
        case .verified(let status):
            settings.updateRemoteHostState(for: host) { state in
                install(account, in: &state)
                state.desiredAccountID = account.id
                state.verifiedAccount = mergedRemoteAccount(account, status: status)
                state.detectedAccountID = nil
                state.verificationStatus = .verified
                state.lastVerificationError = nil
            }
            markAccountActivated(account.id)
            setConnectionState(.connected, for: host.destination)
        case .notVerified(let message, let detectedAccountID):
            setConnectionState(.connected, for: host.destination)
            settings.updateRemoteHostState(for: host) { state in
                install(account, in: &state)
                state.desiredAccountID = account.id
                state.verifiedAccount = nil
                state.detectedAccountID = detectedAccountID
                state.verificationStatus = .failed
                state.lastVerificationError = message
            }
        case .failed(let message, let hostReachable):
            setConnectionState(hostReachable ? .connected : .disconnected, for: host.destination)
            settings.updateRemoteHostState(for: host) { state in
                if recordsInstalledAccountOnFailure {
                    install(account, in: &state)
                }
                state.desiredAccountID = account.id
                state.verifiedAccount = nil
                state.detectedAccountID = nil
                state.verificationStatus = .failed
                state.lastVerificationError = message
            }
        }
    }

    func removeHost(_ hostState: PersistedRemoteHostState) {
        persistRemoteAccountIntoCatalogIfNeeded(hostState.verifiedAccount)
        settings.removeRemoteHost(destination: hostState.host.destination)
        connectionStates.removeValue(forKey: hostState.host.destination)
    }

    func beginReverification(hostState: PersistedRemoteHostState) -> CodexAccount? {
        guard hostState.verificationStatus != .verifying else { return nil }
        guard let baseAccount = baseAccountForRemoteRefresh(hostState: hostState) else { return nil }

        setConnectionState(.syncing, for: hostState.host.destination)
        settings.updateRemoteHostState(for: hostState.host) { state in
            state.verificationStatus = .verifying
            state.lastVerificationError = nil
            if state.desiredAccountID == nil {
                state.desiredAccountID = baseAccount.id
            }
        }
        return baseAccount
    }

    func beginAdoptingDetectedAccount(hostState: PersistedRemoteHostState, accountID: UUID) -> CodexAccount? {
        guard let detectedAccount = accounts().first(where: { $0.id == accountID }) else { return nil }

        setConnectionState(.syncing, for: hostState.host.destination)
        settings.updateRemoteHostState(for: hostState.host) { state in
            state.desiredAccountID = detectedAccount.id
            state.detectedAccountID = detectedAccount.id
            state.verificationStatus = .verifying
            state.lastVerificationError = nil
        }
        return detectedAccount
    }

    func refreshAll(markSyncing: Bool = true, onHostRefreshed: @escaping @MainActor () -> Void) {
        for hostState in settings.remoteHostStates {
            guard let baseAccount = baseAccountForRemoteRefresh(hostState: hostState) else {
                markMissingBaseAccountIfNeeded(hostState)
                continue
            }
            if markSyncing {
                setConnectionState(.syncing, for: hostState.host.destination)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refresh(host: hostState.host, baseAccount: baseAccount, fallbackConnectionState: .disconnected)
                onHostRefreshed()
            }
        }
    }

    func refresh(
        host: RemoteHost,
        baseAccount: CodexAccount,
        fallbackConnectionState: RemoteHostConnectionState
    ) async {
        do {
            let status = try await remoteHostClient.readCurrentAccountStatus(on: host)
            switch remoteHostAccountVerifier.verify(
                status: status,
                expectedAccount: baseAccount,
                among: accounts()
            ) {
            case .verified(let verifiedStatus):
                let refreshedAccount = mergedRemoteAccount(baseAccount, status: verifiedStatus)
                let previousVerifiedAccountID = settings.remoteHostState(for: host.destination)?.verifiedAccount?.id
                setConnectionState(.connected, for: host.destination)
                settings.updateRemoteHostState(for: host) { state in
                    state.desiredAccountID = baseAccount.id
                    state.verifiedAccount = refreshedAccount
                    state.detectedAccountID = nil
                    state.verificationStatus = .verified
                    state.lastVerificationError = nil
                }
                if previousVerifiedAccountID != refreshedAccount.id {
                    markAccountActivated(refreshedAccount.id)
                }
            case .notVerified(let matchOutcome):
                persistRemoteAccountIntoCatalogIfNeeded(settings.remoteHostState(for: host.destination)?.verifiedAccount)
                setConnectionState(.connected, for: host.destination)
                settings.updateRemoteHostState(for: host) { state in
                    state.desiredAccountID = baseAccount.id
                    state.verifiedAccount = nil
                    state.detectedAccountID = matchOutcome.matchedAccountID
                    state.verificationStatus = .failed
                    state.lastVerificationError = remoteHostAccountVerifier.failureMessage(
                        for: baseAccount,
                        on: host,
                        among: accounts(),
                        matchOutcome: matchOutcome
                    )
                }
            }
        } catch {
            persistRemoteAccountIntoCatalogIfNeeded(settings.remoteHostState(for: host.destination)?.verifiedAccount)
            let connectionState = Self.isReachableRemoteVerificationFailure(error) ? RemoteHostConnectionState.connected : fallbackConnectionState
            setConnectionState(connectionState, for: host.destination)
            settings.updateRemoteHostState(for: host) { state in
                state.desiredAccountID = baseAccount.id
                state.verifiedAccount = nil
                state.detectedAccountID = nil
                state.verificationStatus = .failed
                state.lastVerificationError = error.localizedDescription
            }
        }
    }

    private func markMissingBaseAccountIfNeeded(_ hostState: PersistedRemoteHostState) {
        guard hostState.desiredAccountID != nil || hostState.verifiedAccount != nil else { return }
        persistRemoteAccountIntoCatalogIfNeeded(hostState.verifiedAccount)
        setConnectionState(.disconnected, for: hostState.host.destination)
        settings.updateRemoteHostState(for: hostState.host) { state in
            state.verifiedAccount = nil
            state.detectedAccountID = nil
            state.verificationStatus = .failed
            state.lastVerificationError = "Saved account for \(hostState.host.displayName) is no longer available on this Mac."
        }
    }

    private func connectionState(for hostState: PersistedRemoteHostState) -> RemoteHostConnectionState {
        connectionStates[hostState.host.destination]
            ?? (hostState.desiredAccountID != nil ? .syncing : .disconnected)
    }

    private func desiredAccount(for hostState: PersistedRemoteHostState) -> CodexAccount? {
        if let canonicalAccount = savedAccountRelinker.resolveCanonicalAccount(
            for: hostState,
            among: accounts()
        ) {
            return canonicalAccount
        }

        guard let desiredAccountID = hostState.desiredAccountID else { return nil }
        if let verifiedAccount = hostState.verifiedAccount, verifiedAccount.id == desiredAccountID {
            return verifiedAccount
        }
        return nil
    }

    private func detectedAccount(for hostState: PersistedRemoteHostState) -> CodexAccount? {
        guard let detectedAccountID = hostState.detectedAccountID else { return nil }
        return accounts().first(where: { $0.id == detectedAccountID })
    }

    private func baseAccountForRemoteRefresh(hostState: PersistedRemoteHostState) -> CodexAccount? {
        if let canonicalAccount = savedAccountRelinker.resolveCanonicalAccount(
            for: hostState,
            among: accounts()
        ) {
            return canonicalAccount
        }

        return hostState.verifiedAccount
    }

    private func setConnectionState(_ state: RemoteHostConnectionState, for hostDestination: String) {
        connectionStates[hostDestination] = state
    }

    private func mergedRemoteAccount(_ baseAccount: CodexAccount, status: CodexAccountStatus) -> CodexAccount {
        var account = baseAccount
        let mergedRateLimits = RemoteRateLimitResolution().preferredRateLimits(
            remote: status.rateLimits,
            fallback: baseAccount.rateLimits,
            candidateAccounts: accounts(),
            baseAccount: baseAccount,
            remoteEmail: status.email
        )
        account.applyRemoteMetadata(
            email: status.email ?? baseAccount.email,
            planType: status.planType ?? baseAccount.planType,
            rateLimits: mergedRateLimits
        )
        account.updatedAt = .now
        return account
    }

    private func persistRemoteAccountIntoCatalogIfNeeded(_ account: CodexAccount?) {
        guard let account else { return }
        persistAccountMetadata(account)
    }

    private func install(_ account: CodexAccount, in state: inout PersistedRemoteHostState) {
        if !state.installedAccountIDs.contains(account.id) {
            state.installedAccountIDs.append(account.id)
        }
    }

    private static func isReachableRemoteVerificationFailure(_ error: Error) -> Bool {
        guard let clientError = error as? RemoteHostClientError else { return false }
        if case .authReadFailed = clientError {
            return true
        }
        return false
    }
}
