import Foundation

enum RemoteHostConnectionState: String, Codable, Equatable {
    case connected
    case disconnected
    case syncing

    var menuTitle: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .syncing:
            return "Syncing"
        }
    }
}

struct RemoteHostMenuState: Codable, Equatable {
    let name: String
    let destination: String
    let connectionState: RemoteHostConnectionState
    let desiredAccount: CodexAccount?
    let activeAccount: CodexAccount?
    let detectedAccount: CodexAccount?
    let verificationStatus: PersistedRemoteHostState.VerificationStatus
    let lastVerificationError: String?
    let deployedAccountIDs: [UUID]

    init(
        name: String,
        destination: String = "",
        connectionState: RemoteHostConnectionState,
        desiredAccount: CodexAccount? = nil,
        activeAccount: CodexAccount?,
        detectedAccount: CodexAccount? = nil,
        verificationStatus: PersistedRemoteHostState.VerificationStatus = .verified,
        lastVerificationError: String? = nil,
        deployedAccountIDs: [UUID] = []
    ) {
        self.name = name
        self.destination = destination
        self.connectionState = connectionState
        self.desiredAccount = desiredAccount
        self.activeAccount = activeAccount
        self.detectedAccount = detectedAccount
        self.verificationStatus = verificationStatus
        self.lastVerificationError = lastVerificationError
        self.deployedAccountIDs = deployedAccountIDs
    }

    func hasDeployedAccount(_ account: CodexAccount) -> Bool {
        deployedAccountIDs.contains(account.id)
    }

    var displayAccount: CodexAccount? {
        activeAccount ?? detectedAccount ?? desiredAccount
    }

    var isVerified: Bool {
        activeAccount != nil && verificationStatus == .verified
    }
}
