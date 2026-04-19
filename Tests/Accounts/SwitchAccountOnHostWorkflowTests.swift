import Foundation
import Testing

@testable import CodexPill

struct SwitchAccountOnHostWorkflowTests {
    @Test
    func runInstallsBeforeSwitchingWhenAccountIsMissingOnHost() async throws {
        let account = makeAccount(name: "Research")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(installationState: .missing)
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        try await workflow.run(account: account, on: host)

        #expect(client.events == [
            .installationState(account.id, host.displayName),
            .install(account.id, host.displayName),
            .switchAccount(account.id, host.displayName)
        ])
    }

    @Test
    func runSwitchesDirectlyWhenAccountIsAlreadyInstalled() async throws {
        let account = makeAccount(name: "Research")
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = RemoteHostClientSpy(installationState: .installed)
        let workflow = SwitchAccountOnHostWorkflow(remoteHostClient: client)

        try await workflow.run(account: account, on: host)

        #expect(client.events == [
            .installationState(account.id, host.displayName),
            .switchAccount(account.id, host.displayName)
        ])
    }

    private func makeAccount(name: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "\(name.lowercased())@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }
}

private final class RemoteHostClientSpy: RemoteHostSwitching {
    enum Event: Equatable {
        case installationState(UUID, String)
        case install(UUID, String)
        case switchAccount(UUID, String)
    }

    let installationState: RemoteHostAccountInstallationState
    private(set) var events: [Event] = []

    init(installationState: RemoteHostAccountInstallationState) {
        self.installationState = installationState
    }

    func testConnection(to host: RemoteHost) async throws {}

    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState {
        events.append(.installationState(account.id, host.displayName))
        return installationState
    }

    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        events.append(.install(account.id, host.displayName))
    }

    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        events.append(.switchAccount(account.id, host.displayName))
    }

    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)
    }
}
