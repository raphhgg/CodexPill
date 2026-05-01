import Foundation

struct PersistedRemoteHostState: Codable, Equatable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case host
        case installedAccountIDs
        case desiredAccountID
        case verifiedAccount
        case detectedAccountID
        case verificationStatus
        case lastVerificationError
        case activeAccount
    }

    enum VerificationStatus: String, Codable, Equatable {
        case unverified
        case verifying
        case verified
        case failed
    }

    var host: RemoteHost
    var installedAccountIDs: [UUID]
    var desiredAccountID: UUID?
    var verifiedAccount: CodexAccount?
    var detectedAccountID: UUID?
    var verificationStatus: VerificationStatus
    var lastVerificationError: String?

    var id: String {
        host.destination
    }

    var activeAccount: CodexAccount? {
        get { verifiedAccount }
        set {
            verifiedAccount = newValue
            detectedAccountID = nil
            verificationStatus = newValue == nil ? .unverified : .verified
            lastVerificationError = nil
            if desiredAccountID == nil {
                desiredAccountID = newValue?.id
            }
        }
    }

    init(
        host: RemoteHost,
        installedAccountIDs: [UUID] = [],
        desiredAccountID: UUID? = nil,
        verifiedAccount: CodexAccount? = nil,
        detectedAccountID: UUID? = nil,
        verificationStatus: VerificationStatus? = nil,
        lastVerificationError: String? = nil
    ) {
        self.host = host
        self.installedAccountIDs = installedAccountIDs
        self.desiredAccountID = desiredAccountID
        self.verifiedAccount = verifiedAccount
        self.detectedAccountID = detectedAccountID
        self.verificationStatus = verificationStatus ?? (verifiedAccount == nil ? .unverified : .verified)
        self.lastVerificationError = lastVerificationError
    }

    init(host: RemoteHost, installedAccountIDs: [UUID] = [], activeAccount: CodexAccount? = nil) {
        self.init(
            host: host,
            installedAccountIDs: installedAccountIDs,
            desiredAccountID: activeAccount?.id,
            verifiedAccount: activeAccount,
            verificationStatus: activeAccount == nil ? .unverified : .verified,
            lastVerificationError: nil
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        host = try container.decode(RemoteHost.self, forKey: .host)
        installedAccountIDs = try container.decodeIfPresent([UUID].self, forKey: .installedAccountIDs) ?? []

        let desiredAccountID = try container.decodeIfPresent(UUID.self, forKey: .desiredAccountID)
        let verifiedAccount = try container.decodeIfPresent(CodexAccount.self, forKey: .verifiedAccount)
        let detectedAccountID = try container.decodeIfPresent(UUID.self, forKey: .detectedAccountID)
        let verificationStatus = try container.decodeIfPresent(VerificationStatus.self, forKey: .verificationStatus)
        let lastVerificationError = try container.decodeIfPresent(String.self, forKey: .lastVerificationError)

        if desiredAccountID != nil || verifiedAccount != nil || verificationStatus != nil || detectedAccountID != nil || lastVerificationError != nil {
            self.desiredAccountID = desiredAccountID
            self.verifiedAccount = verifiedAccount
            self.detectedAccountID = detectedAccountID
            self.verificationStatus = verificationStatus ?? (verifiedAccount == nil ? .unverified : .verified)
            self.lastVerificationError = lastVerificationError
            return
        }

        let legacyActiveAccount = try container.decodeIfPresent(CodexAccount.self, forKey: .activeAccount)
        self.desiredAccountID = legacyActiveAccount?.id
        self.verifiedAccount = nil
        self.detectedAccountID = nil
        self.verificationStatus = legacyActiveAccount == nil ? .unverified : .unverified
        self.lastVerificationError = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(installedAccountIDs, forKey: .installedAccountIDs)
        try container.encodeIfPresent(desiredAccountID, forKey: .desiredAccountID)
        try container.encodeIfPresent(verifiedAccount, forKey: .verifiedAccount)
        try container.encodeIfPresent(detectedAccountID, forKey: .detectedAccountID)
        try container.encode(verificationStatus, forKey: .verificationStatus)
        try container.encodeIfPresent(lastVerificationError, forKey: .lastVerificationError)
    }
}
