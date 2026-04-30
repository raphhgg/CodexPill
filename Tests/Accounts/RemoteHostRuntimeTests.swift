import Foundation
import Testing

@testable import CodexPill

@MainActor
struct RemoteHostRuntimeTests {
    @Test
    func failedManualSwitchDoesNotRecordAccountAsInstalled() throws {
        let account = makeAccount(name: "Business 4")
        let host = RemoteHost(destination: "user@debian-vm", displayName: "debian-vm")
        let settings = makeSettings()
        settings.updateRemoteHostState(for: host) { state in
            state.installedAccountIDs = []
        }
        let runtime = makeRuntime(settings: settings, accounts: [account])

        runtime.applySwitchOutcome(
            .failed("Remote command failed.", hostReachable: true),
            account: account,
            host: host
        )

        let state = try #require(settings.remoteHostState(for: host.destination))
        #expect(state.installedAccountIDs.isEmpty)
        #expect(state.desiredAccountID == account.id)
        #expect(state.verificationStatus == .failed)
    }

    @Test
    func failedAddHostInstallFlowRecordsAccountAsInstalled() throws {
        let account = makeAccount(name: "Business 4")
        let host = RemoteHost(destination: "user@debian-vm", displayName: "debian-vm")
        let settings = makeSettings()
        let runtime = makeRuntime(settings: settings, accounts: [account])

        runtime.applySwitchOutcome(
            .failed("Remote command failed.", hostReachable: true),
            account: account,
            host: host,
            recordsInstalledAccountOnFailure: true
        )

        let state = try #require(settings.remoteHostState(for: host.destination))
        #expect(state.installedAccountIDs == [account.id])
        #expect(state.desiredAccountID == account.id)
        #expect(state.verificationStatus == .failed)
    }

    @Test
    func refreshFailurePreservesPreviousVerifiedRemoteMetadataInCatalog() async throws {
        let account = makeAccount(name: "Business 4", email: "business-4@example.com")
        var remoteSnapshot = account
        remoteSnapshot.email = "remote-business-4@example.com"
        remoteSnapshot.updatedAt = Date(timeIntervalSince1970: 1_000)
        let host = RemoteHost(destination: "user@debian-vm", displayName: "debian-vm")
        let settings = makeSettings()
        settings.updateRemoteHostState(for: host) { state in
            state.desiredAccountID = account.id
            state.verifiedAccount = remoteSnapshot
            state.verificationStatus = .verified
        }
        var persistedAccounts: [CodexAccount] = []
        let runtime = makeRuntime(
            settings: settings,
            remoteHostClient: RemoteHostClientFixture(readStatusResult: .failure(RemoteHostClientError.unavailable)),
            accounts: [account],
            persistAccountMetadata: { persistedAccounts.append($0) }
        )

        await runtime.refresh(host: host, baseAccount: account, fallbackConnectionState: .disconnected)

        #expect(persistedAccounts.map(\.email) == ["remote-business-4@example.com"])
        let state = try #require(settings.remoteHostState(for: host.destination))
        #expect(state.verifiedAccount == nil)
        #expect(state.verificationStatus == .failed)
        #expect(state.lastVerificationError == RemoteHostClientError.unavailable.localizedDescription)
    }

    @Test
    func refreshAllRefreshesOtherHostsWhileOneHostIsSlow() async throws {
        let slowAccount = makeAccount(name: "Business 4", email: "business-4@example.com")
        let fastAccount = makeAccount(name: "Business 2", email: "business-2@example.com")
        let slowHost = RemoteHost(destination: "user@slow-host", displayName: "slow-host")
        let fastHost = RemoteHost(destination: "user@fast-host", displayName: "fast-host")
        let settings = makeSettings()
        settings.updateRemoteHostState(for: slowHost) { state in
            state.desiredAccountID = slowAccount.id
            state.verificationStatus = .verified
        }
        settings.updateRemoteHostState(for: fastHost) { state in
            state.desiredAccountID = fastAccount.id
            state.verificationStatus = .verified
        }
        let client = RemoteHostClientFixture(
            statuses: [
                slowHost.destination: CodexAccountStatus(email: slowAccount.email, planType: "team", rateLimits: nil),
                fastHost.destination: CodexAccountStatus(email: fastAccount.email, planType: "team", rateLimits: nil)
            ],
            delayedDestinations: [slowHost.destination]
        )
        let runtime = makeRuntime(
            settings: settings,
            remoteHostClient: client,
            accounts: [slowAccount, fastAccount]
        )
        var refreshedCount = 0

        runtime.refreshAll {
            refreshedCount += 1
        }

        try await Task.sleep(for: .milliseconds(60))

        let fastState = try #require(settings.remoteHostState(for: fastHost.destination))
        let slowState = try #require(settings.remoteHostState(for: slowHost.destination))
        #expect(refreshedCount == 1)
        #expect(fastState.verifiedAccount?.id == fastAccount.id)
        #expect(slowState.verifiedAccount == nil)

        try await Task.sleep(for: .milliseconds(220))

        let completedSlowState = try #require(settings.remoteHostState(for: slowHost.destination))
        #expect(refreshedCount == 2)
        #expect(completedSlowState.verifiedAccount?.id == slowAccount.id)
    }

    private func makeRuntime(
        settings: AppSettings,
        remoteHostClient: RemoteHostClient = RemoteHostClientFixture(),
        accounts: [CodexAccount],
        persistAccountMetadata: @escaping (CodexAccount) -> Void = { _ in },
        markAccountActivated: @escaping (UUID) -> Void = { _ in }
    ) -> RemoteHostRuntime {
        RemoteHostRuntime(
            settings: settings.remoteHostSettings,
            remoteHostClient: remoteHostClient,
            accounts: { accounts },
            persistAccountMetadata: persistAccountMetadata,
            markAccountActivated: markAccountActivated
        )
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "RemoteHostRuntimeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(userDefaults: defaults)
    }

    private func makeAccount(
        name: String,
        email: String = "business@example.com"
    ) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: email,
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}

private struct RemoteHostClientFixture: RemoteHostClient {
    var readStatusResult: Result<CodexAccountStatus, Error> = .success(
        CodexAccountStatus(email: "business@example.com", planType: "team", rateLimits: nil)
    )
    var statuses: [String: CodexAccountStatus] = [:]
    var delayedDestinations: Set<String> = []

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func refreshCodexAppServer(on host: RemoteHost) async throws {}

    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        if delayedDestinations.contains(host.destination) {
            try await Task.sleep(for: .milliseconds(180))
        }
        if let status = statuses[host.destination] {
            return status
        }
        return try readStatusResult.get()
    }
}
