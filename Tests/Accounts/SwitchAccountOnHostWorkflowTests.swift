import Foundation
import Testing

@testable import CodexPill

struct SwitchAccountOnHostWorkflowTests {
    @Test
    func runInstallsBeforeSwitchingWhenAccountIsMissingOnHost() async throws {
        let account = makeAccount(name: "Research")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .missing,
            status: CodexAccountStatus(email: account.email, planType: account.planType, rateLimits: nil)
        )
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        let result = try await workflow.run(account: account, on: host, among: [account])

        #expect(client.events == [
            .installationState(account.id, host.displayName),
            .install(account.id, host.displayName),
            .switchAccount(account.id, host.displayName),
            .refreshRuntime(host.displayName),
            .readStatus(host.displayName)
        ])
        #expect(result == .verified(CodexAccountStatus(email: account.email, planType: account.planType, rateLimits: nil)))
    }

    @Test
    func runSwitchesDirectlyWhenAccountIsAlreadyInstalled() async throws {
        let account = makeAccount(name: "Research")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .installed,
            status: CodexAccountStatus(email: account.email, planType: account.planType, rateLimits: nil)
        )
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        let result = try await workflow.run(account: account, on: host, among: [account])

        #expect(client.events == [
            .installationState(account.id, host.displayName),
            .switchAccount(account.id, host.displayName),
            .refreshRuntime(host.displayName),
            .readStatus(host.displayName)
        ])
        #expect(result == .verified(CodexAccountStatus(email: account.email, planType: account.planType, rateLimits: nil)))
    }

    @Test
    func runStopsBeforeSwitchWhenInstallFails() async {
        let account = makeAccount(name: "Research")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .missing,
            installError: RemoteHostClientError.commandFailed("scp: Permission denied")
        )
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        await #expect(throws: RemoteHostClientError.commandFailed("scp: Permission denied")) {
            _ = try await workflow.run(account: account, on: host, among: [account])
        }

        #expect(client.events == [
            .installationState(account.id, host.displayName),
            .install(account.id, host.displayName)
        ])
    }

    @Test
    func runSurfacesSwitchFailuresAfterInstallSucceeds() async {
        let account = makeAccount(name: "Research")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .missing,
            switchError: RemoteHostClientError.commandFailed("cp: auth.json: Permission denied")
        )
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        await #expect(throws: RemoteHostClientError.commandFailed("cp: auth.json: Permission denied")) {
            _ = try await workflow.run(account: account, on: host, among: [account])
        }

        #expect(client.events == [
            .installationState(account.id, host.displayName),
            .install(account.id, host.displayName),
            .switchAccount(account.id, host.displayName)
        ])
    }

    @Test
    func testConnectionDelegatesToRemoteClient() async throws {
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(installationState: .installed)
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        try await workflow.testConnection(to: host)

        #expect(client.events == [.testConnection(host.displayName)])
    }

    @Test
    func runReturnsNotVerifiedWhenRemoteProbeMatchesDifferentSavedAccount() async throws {
        let target = makeAccount(name: "Research")
        let other = makeAccount(name: "Business")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .installed,
            status: CodexAccountStatus(email: other.email, planType: other.planType, rateLimits: nil)
        )
        let workflow = SwitchAccountOnHostWorkflow(
            remoteHostClient: client,
            verificationProbeDelays: [.zero, .zero]
        )

        let result = try await workflow.run(account: target, on: host, among: [target, other])

        #expect(result == .notVerified(.uniqueRemoteIdentity(other.id)))
        #expect(client.events == [
            .installationState(target.id, host.displayName),
            .switchAccount(target.id, host.displayName),
            .refreshRuntime(host.displayName),
            .readStatus(host.displayName),
            .readStatus(host.displayName)
        ])
    }

    @Test
    func runReturnsNotVerifiedWhenRemoteProbeIsAmbiguousAcrossSavedAccounts() async throws {
        let target = makeAccount(name: "Personal", email: "shared@example.com")
        let duplicate = makeAccount(name: "Business", email: "shared@example.com")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .installed,
            status: CodexAccountStatus(email: "shared@example.com", planType: target.planType, rateLimits: nil)
        )
        let workflow = SwitchAccountOnHostWorkflow(
            remoteHostClient: client,
            verificationProbeDelays: [.zero, .zero]
        )

        let result = try await workflow.run(account: target, on: host, among: [target, duplicate])

        #expect(result == .notVerified(.ambiguousRemoteIdentity([duplicate.id, target.id].sorted { $0.uuidString < $1.uuidString })))
    }

    @Test
    func runVerifiesExpectedAccountWhenRemoteProbeIncludesMatchingFingerprintForSharedEmail() async throws {
        let target = makeAccount(
            name: "Business 2",
            email: "shared@example.com",
            snapshotFingerprint: "target-fingerprint"
        )
        let duplicate = makeAccount(
            name: "Personal 1",
            email: "shared@example.com",
            snapshotFingerprint: "other-fingerprint"
        )
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .installed,
            status: CodexAccountStatus(
                email: "shared@example.com",
                planType: target.planType,
                rateLimits: nil,
                snapshotFingerprint: "target-fingerprint"
            )
        )
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        let result = try await workflow.run(account: target, on: host, among: [target, duplicate])

        #expect(result == .verified(CodexAccountStatus(
            email: "shared@example.com",
            planType: target.planType,
            rateLimits: nil,
            snapshotFingerprint: "target-fingerprint"
        )))
    }

    @Test
    func runRetriesVerificationWhenRemoteProbeIsInitiallyStale() async throws {
        let target = makeAccount(name: "Research")
        let previous = makeAccount(name: "Business")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .installed,
            statuses: [
                CodexAccountStatus(email: previous.email, planType: previous.planType, rateLimits: nil),
                CodexAccountStatus(email: target.email, planType: target.planType, rateLimits: nil)
            ]
        )
        let workflow = SwitchAccountOnHostWorkflow(
            remoteHostClient: client,
            verificationProbeDelays: [.zero, .zero]
        )

        let result = try await workflow.run(account: target, on: host, among: [target, previous])

        #expect(result == .verified(CodexAccountStatus(email: target.email, planType: target.planType, rateLimits: nil)))
        #expect(client.events == [
            .installationState(target.id, host.displayName),
            .switchAccount(target.id, host.displayName),
            .refreshRuntime(host.displayName),
            .readStatus(host.displayName),
            .readStatus(host.displayName)
        ])
    }

    @Test
    func runStopsAndFailsWhenRuntimeRefreshFails() async {
        let account = makeAccount(name: "Research")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .installed,
            refreshError: RemoteHostClientError.commandFailed("Remote Codex app-server failed to restart")
        )
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        await #expect(throws: RemoteHostClientError.commandFailed("Remote Codex app-server failed to restart")) {
            _ = try await workflow.run(account: account, on: host, among: [account])
        }

        #expect(client.events == [
            .installationState(account.id, host.displayName),
            .switchAccount(account.id, host.displayName),
            .refreshRuntime(host.displayName)
        ])
    }

    @Test
    func runSurfacesProbeFailuresAfterSwitchCompletes() async {
        let account = makeAccount(name: "Research")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(
            installationState: .installed,
            statusError: RemoteHostClientError.commandFailed("Remote app-server unavailable")
        )
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        await #expect(throws: RemoteHostClientError.commandFailed("Remote app-server unavailable")) {
            _ = try await workflow.run(account: account, on: host, among: [account])
        }

        #expect(client.events == [
            .installationState(account.id, host.displayName),
            .switchAccount(account.id, host.displayName),
            .refreshRuntime(host.displayName),
            .readStatus(host.displayName)
        ])
    }

    private func makeAccount(
        name: String,
        email: String? = nil,
        snapshotFingerprint: String = UUID().uuidString
    ) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: email ?? "\(name.lowercased())@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: snapshotFingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email ?? "\(name.lowercased())@example.com")
            )
        )
    }
}

private final class RemoteHostClientSpy: RemoteHostSwitching {
    enum Event: Equatable {
        case testConnection(String)
        case installationState(UUID, String)
        case install(UUID, String)
        case switchAccount(UUID, String)
        case refreshRuntime(String)
        case readStatus(String)
    }

    let installationState: RemoteHostAccountInstallationState
    let statuses: [CodexAccountStatus]
    let installError: Error?
    let switchError: Error?
    let refreshError: Error?
    let statusError: Error?
    private(set) var events: [Event] = []
    private var nextStatusIndex = 0

    init(
        installationState: RemoteHostAccountInstallationState,
        status: CodexAccountStatus? = nil,
        statuses: [CodexAccountStatus] = [],
        installError: Error? = nil,
        switchError: Error? = nil,
        refreshError: Error? = nil,
        statusError: Error? = nil
    ) {
        self.installationState = installationState
        self.statuses = statuses.isEmpty ? [status ?? CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)] : statuses
        self.installError = installError
        self.switchError = switchError
        self.refreshError = refreshError
        self.statusError = statusError
    }

    func testConnection(to host: RemoteHost) async throws {
        events.append(.testConnection(host.displayName))
    }

    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState {
        events.append(.installationState(account.id, host.displayName))
        return installationState
    }

    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        events.append(.install(account.id, host.displayName))
        if let installError {
            throw installError
        }
    }

    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        events.append(.switchAccount(account.id, host.displayName))
        if let switchError {
            throw switchError
        }
    }

    func refreshCodexAppServer(on host: RemoteHost) async throws {
        events.append(.refreshRuntime(host.displayName))
        if let refreshError {
            throw refreshError
        }
    }

    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        events.append(.readStatus(host.displayName))
        if let statusError {
            throw statusError
        }
        let index = min(nextStatusIndex, statuses.count - 1)
        let status = statuses[index]
        nextStatusIndex += 1
        return status
    }
}
