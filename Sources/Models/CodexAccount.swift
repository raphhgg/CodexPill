import Foundation

struct CodexAccountIdentity: Codable, Hashable {
    var snapshotFingerprint: String?
    var remoteIdentity: CodexRemoteAccountIdentity?

    static let empty = Self(snapshotFingerprint: nil, remoteIdentity: nil)
}

struct CodexRemoteAccountIdentity: Codable, Hashable {
    let normalizedEmailAddress: String

    init?(emailAddress: String?) {
        let normalized = emailAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalized.isEmpty else { return nil }
        self.normalizedEmailAddress = normalized
    }
}

struct CodexAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var snapshotFileName: String
    var createdAt: Date
    var updatedAt: Date
    var email: String?
    var planType: String?
    var rateLimits: CodexRateLimitSnapshot?
    var identity: CodexAccountIdentity

    init(
        id: UUID,
        name: String,
        snapshotFileName: String,
        createdAt: Date,
        updatedAt: Date,
        email: String?,
        planType: String?,
        rateLimits: CodexRateLimitSnapshot?,
        identity: CodexAccountIdentity = .empty
    ) {
        self.id = id
        self.name = name
        self.snapshotFileName = snapshotFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.email = email
        self.planType = planType
        self.rateLimits = rateLimits
        self.identity = identity
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case snapshotFileName
        case createdAt
        case updatedAt
        case email
        case planType
        case rateLimits
        case identity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        snapshotFileName = try container.decode(String.self, forKey: .snapshotFileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        rateLimits = try container.decodeIfPresent(CodexRateLimitSnapshot.self, forKey: .rateLimits)
        identity = try container.decodeIfPresent(CodexAccountIdentity.self, forKey: .identity)
            ?? CodexAccountIdentity(
                snapshotFingerprint: nil,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
    }

    var resolvedRemoteIdentity: CodexRemoteAccountIdentity? {
        identity.remoteIdentity ?? CodexRemoteAccountIdentity(emailAddress: email)
    }

    mutating func applyRemoteMetadata(
        email: String?,
        planType: String?,
        rateLimits: CodexRateLimitSnapshot?
    ) {
        self.email = email
        self.planType = planType
        self.rateLimits = rateLimits
        identity.remoteIdentity = CodexRemoteAccountIdentity(emailAddress: email)
    }
}
