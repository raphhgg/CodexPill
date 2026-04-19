import Foundation

struct SwitchAccountOnHostWorkflow {
    private let remoteHostClient: RemoteHostSwitching

    init(remoteHostClient: RemoteHostSwitching) {
        self.remoteHostClient = remoteHostClient
    }

    func testConnection(to host: RemoteHost) async throws {
        try await remoteHostClient.testConnection(to: host)
    }

    func run(account: CodexAccount, on host: RemoteHost) async throws {
        let installationState = try await remoteHostClient.installationState(for: account, on: host)
        if installationState == .missing {
            try await remoteHostClient.installAccount(account, on: host)
        }
        try await remoteHostClient.switchToAccount(account, on: host)
    }
}
