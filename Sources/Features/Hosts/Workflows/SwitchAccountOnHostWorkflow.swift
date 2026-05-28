import Foundation

struct SwitchAccountOnHostWorkflow: Sendable {
    private let connectionChecker: RemoteHostConnectionChecking
    private let accountInstaller: RemoteHostAccountInstalling
    private let accountSwitcher: RemoteHostAccountSwitching
    private let appServerRefresher: RemoteHostCodexAppServerRefreshing
    private let accountStatusReader: RemoteHostAccountStatusReading
    private let accountVerifier: RemoteHostAccountVerifier
    private let verificationProbeDelays: [Duration]

    init(
        connectionChecker: RemoteHostConnectionChecking,
        accountInstaller: RemoteHostAccountInstalling,
        accountSwitcher: RemoteHostAccountSwitching,
        appServerRefresher: RemoteHostCodexAppServerRefreshing,
        accountStatusReader: RemoteHostAccountStatusReading,
        accountVerifier: RemoteHostAccountVerifier = RemoteHostAccountVerifier(),
        verificationProbeDelays: [Duration] = [.zero, .seconds(1), .seconds(2)]
    ) {
        self.connectionChecker = connectionChecker
        self.accountInstaller = accountInstaller
        self.accountSwitcher = accountSwitcher
        self.appServerRefresher = appServerRefresher
        self.accountStatusReader = accountStatusReader
        self.accountVerifier = accountVerifier
        self.verificationProbeDelays = verificationProbeDelays
    }

    init(
        remoteHostSwitchOperations: RemoteHostSwitchWorkflowOperations,
        accountVerifier: RemoteHostAccountVerifier = RemoteHostAccountVerifier(),
        verificationProbeDelays: [Duration] = [.zero, .seconds(1), .seconds(2)]
    ) {
        self.init(
            connectionChecker: remoteHostSwitchOperations,
            accountInstaller: remoteHostSwitchOperations,
            accountSwitcher: remoteHostSwitchOperations,
            appServerRefresher: remoteHostSwitchOperations,
            accountStatusReader: remoteHostSwitchOperations,
            accountVerifier: accountVerifier,
            verificationProbeDelays: verificationProbeDelays
        )
    }

    func testConnection(to host: RemoteHost) async throws {
        try await connectionChecker.testConnection(to: host)
    }

    func run(
        account: CodexAccount,
        on host: RemoteHost,
        among accounts: [CodexAccount]
    ) async throws -> RemoteHostSwitchVerificationResult {
        let installationState = try await accountInstaller.installationState(for: account, on: host)
        if installationState == .missing {
            try await accountInstaller.installAccount(account, on: host)
        }
        try await accountSwitcher.switchToAccount(account, on: host)
        try await appServerRefresher.refreshCodexAppServer(on: host)

        var latestVerificationResult: RemoteHostSwitchVerificationResult?

        for (index, delay) in verificationProbeDelays.enumerated() {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }

            let status = try await accountStatusReader.readCurrentAccountStatus(on: host)
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
