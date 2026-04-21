import Foundation

struct SwitchAccountOnHostWorkflow {
    private let remoteHostClient: RemoteHostSwitching
    private let accountVerifier: RemoteHostAccountVerifier
    private let verificationProbeDelays: [Duration]

    init(
        remoteHostClient: RemoteHostSwitching,
        accountVerifier: RemoteHostAccountVerifier = RemoteHostAccountVerifier(),
        verificationProbeDelays: [Duration] = [.zero, .seconds(1), .seconds(2)]
    ) {
        self.remoteHostClient = remoteHostClient
        self.accountVerifier = accountVerifier
        self.verificationProbeDelays = verificationProbeDelays
    }

    func testConnection(to host: RemoteHost) async throws {
        try await remoteHostClient.testConnection(to: host)
    }

    func run(
        account: CodexAccount,
        on host: RemoteHost,
        among accounts: [CodexAccount]
    ) async throws -> RemoteHostSwitchVerificationResult {
        let installationState = try await remoteHostClient.installationState(for: account, on: host)
        if installationState == .missing {
            try await remoteHostClient.installAccount(account, on: host)
        }
        try await remoteHostClient.switchToAccount(account, on: host)
        try await remoteHostClient.refreshCodexAppServer(on: host)

        var latestVerificationResult: RemoteHostSwitchVerificationResult?

        for (index, delay) in verificationProbeDelays.enumerated() {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }

            let status = try await remoteHostClient.readCurrentAccountStatus(on: host)
            let verificationResult = accountVerifier.verify(
                status: status,
                expectedAccount: account,
                among: accounts
            )
            latestVerificationResult = verificationResult

            if case .verified = verificationResult {
                return verificationResult
            }

            if index == verificationProbeDelays.count - 1 {
                break
            }
        }

        if let latestVerificationResult {
            return latestVerificationResult
        }

        throw CocoaError(.coderReadCorrupt)
    }
}
