import Foundation
import Testing

@testable import CodexPill

@MainActor
struct RemoteHostRuntimeTests {
    @Test
    func failedManualSwitchDoesNotRecordAccountAsInstalled() throws {
        let account = makeAccount(name: "Business 4", email: "business@example.com")
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
        let account = makeAccount(name: "Business 4", email: "business@example.com")
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
            accountStatusReader: RemoteHostClientFixture(readStatusResult: .failure(RemoteHostClientError.unavailable)),
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
            accountStatusReader: client,
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

    @Test
    func concurrentRefreshesForOneHostShareOneRemoteRead() async throws {
        let account = makeAccount(name: "Business 4", email: "business-4@example.com")
        let host = RemoteHost(destination: "user@debian-vm", displayName: "debian-vm")
        let settings = makeSettings()
        settings.updateRemoteHostState(for: host) { state in
            state.desiredAccountID = account.id
            state.verificationStatus = .verified
        }
        let client = GatedRemoteHostClient(email: account.email)
        let runtime = makeRuntime(settings: settings, accountStatusReader: client, accounts: [account])
        var refreshedCount = 0

        runtime.refreshAll { refreshedCount += 1 }
        runtime.refreshAll { refreshedCount += 1 }
        runtime.refreshAll { refreshedCount += 1 }
        try await client.waitForReads(1)
        await client.openGate()
        try await waitUntil { refreshedCount == 3 }

        #expect(await client.readCount == 1)
        #expect(settings.remoteHostState(for: host.destination)?.verifiedAccount?.id == account.id)

        runtime.refreshAll { refreshedCount += 1 }
        try await waitUntil { refreshedCount == 4 }

        #expect(await client.readCount == 2)
    }

    @Test
    func refreshForAnotherAccountRunsAgainAfterTheInFlightRefresh() async throws {
        let previousAccount = makeAccount(name: "Business 2", email: "business-2@example.com")
        let currentAccount = makeAccount(name: "Business 4", email: "business-4@example.com")
        let host = RemoteHost(destination: "user@debian-vm", displayName: "debian-vm")
        let settings = makeSettings()
        let client = GatedRemoteHostClient(email: currentAccount.email)
        let runtime = makeRuntime(
            settings: settings,
            accountStatusReader: client,
            accounts: [previousAccount, currentAccount]
        )

        let previousRefresh = Task {
            await runtime.refresh(host: host, baseAccount: previousAccount, fallbackConnectionState: .disconnected)
        }
        try await client.waitForReads(1)
        let currentRefresh = Task {
            await runtime.refresh(host: host, baseAccount: currentAccount, fallbackConnectionState: .disconnected)
        }
        await client.openGate()
        await previousRefresh.value
        await currentRefresh.value

        #expect(await client.readCount == 2)
        let state = try #require(settings.remoteHostState(for: host.destination))
        #expect(state.verifiedAccount?.id == currentAccount.id)
        #expect(state.verificationStatus == .verified)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw GatedRemoteHostClient.TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeRuntime(
        settings: RemoteHostSettingsStore,
        accountStatusReader: RemoteHostAccountStatusReading = RemoteHostClientFixture(),
        accounts: [CodexAccount],
        persistAccountMetadata: @escaping (CodexAccount) -> Void = { _ in },
        markAccountActivated: @escaping (UUID) -> Void = { _ in }
    ) -> RemoteHostRuntime {
        RemoteHostRuntime(
            settings: settings,
            accountStatusReader: accountStatusReader,
            accounts: { accounts },
            persistAccountMetadata: persistAccountMetadata,
            markAccountActivated: markAccountActivated
        )
    }

    private func makeSettings() -> RemoteHostSettingsStore {
        let suiteName = "RemoteHostRuntimeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RemoteHostSettingsStore(userDefaults: defaults)
    }
}

private struct RemoteHostClientFixture: RemoteHostAccountStatusReading {
    var readStatusResult: Result<CodexAccountStatus, Error> = .success(
        CodexAccountStatus(email: "business@example.com", planType: "team", rateLimits: nil)
    )
    var statuses: [String: CodexAccountStatus] = [:]
    var delayedDestinations: Set<String> = []

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

private actor GatedRemoteHostClient: RemoteHostAccountStatusReading {
    struct TimedOut: Error {}

    private let status: CodexAccountStatus
    private var isGateOpen = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var readCount = 0

    init(email: String?) {
        status = CodexAccountStatus(email: email, planType: "team", rateLimits: nil)
    }

    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        readCount += 1
        if !isGateOpen {
            await withCheckedContinuation { gateWaiters.append($0) }
        }
        return status
    }

    func openGate() {
        isGateOpen = true
        gateWaiters.forEach { $0.resume() }
        gateWaiters = []
    }

    func waitForReads(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while readCount < count {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
