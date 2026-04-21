import Foundation

actor ValidationRemoteHostClient: RemoteHostSwitching {
    private struct HostState {
        var installedAccountIDs: Set<UUID>
        var activeAccount: CodexAccount?
    }

    private var hostsByDestination: [String: HostState]

    init(seedStates: [PersistedRemoteHostState]) {
        var hosts: [String: HostState] = [:]
        for state in seedStates {
            hosts[state.host.destination] = HostState(
                installedAccountIDs: Set(state.installedAccountIDs),
                activeAccount: state.activeAccount
            )
        }
        self.hostsByDestination = hosts
    }

    func testConnection(to host: RemoteHost) async throws {
        _ = ensureHostState(for: host)
    }

    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState {
        let state = ensureHostState(for: host)
        return state.installedAccountIDs.contains(account.id) ? .installed : .missing
    }

    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        var state = ensureHostState(for: host)
        state.installedAccountIDs.insert(account.id)
        hostsByDestination[host.destination] = state
    }

    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        var state = ensureHostState(for: host)
        state.installedAccountIDs.insert(account.id)
        state.activeAccount = account
        hostsByDestination[host.destination] = state
    }

    func refreshCodexAppServer(on host: RemoteHost) async throws {
        _ = ensureHostState(for: host)
    }

    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        let state = ensureHostState(for: host)
        guard let account = state.activeAccount else {
            throw RemoteHostClientError.commandFailed("Validation host \(host.displayName) has no active account.")
        }

        return CodexAccountStatus(
            email: account.email,
            planType: account.planType,
            rateLimits: account.rateLimits
        )
    }

    private func ensureHostState(for host: RemoteHost) -> HostState {
        if let existing = hostsByDestination[host.destination] {
            return existing
        }

        let created = HostState(installedAccountIDs: [], activeAccount: nil)
        hostsByDestination[host.destination] = created
        return created
    }
}
