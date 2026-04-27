import Foundation

struct CodexAccountIdentity: Codable, Hashable {
    var stableAccountID: String?
    var authPrincipalIdentity: CodexAuthPrincipalIdentity?
    var workspaceIdentity: CodexWorkspaceIdentity?
    var snapshotFingerprint: String?
    var remoteIdentity: CodexRemoteAccountIdentity?

    init(
        stableAccountID: String? = nil,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        workspaceIdentity: CodexWorkspaceIdentity? = nil,
        snapshotFingerprint: String? = nil,
        remoteIdentity: CodexRemoteAccountIdentity? = nil
    ) {
        self.stableAccountID = stableAccountID
        self.authPrincipalIdentity = authPrincipalIdentity
        self.workspaceIdentity = workspaceIdentity
        self.snapshotFingerprint = snapshotFingerprint
        self.remoteIdentity = remoteIdentity
    }

    static let empty = Self(
        stableAccountID: nil,
        authPrincipalIdentity: nil,
        workspaceIdentity: nil,
        snapshotFingerprint: nil,
        remoteIdentity: nil
    )
}

struct CodexAuthPrincipalIdentity: Codable, Hashable {
    let subject: String?
    let chatGPTUserID: String?

    init(subject: String?, chatGPTUserID: String?) {
        let trimmedSubject = subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChatGPTUserID = chatGPTUserID?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.subject = trimmedSubject?.isEmpty == false ? trimmedSubject : nil
        self.chatGPTUserID = trimmedChatGPTUserID?.isEmpty == false ? trimmedChatGPTUserID : nil
    }

    var isMeaningful: Bool {
        subject != nil || chatGPTUserID != nil
    }
}

struct CodexWorkspaceIdentity: Codable, Hashable {
    let workspaceAccountID: String?
    let workspaceLabel: String?

    init(workspaceAccountID: String?, workspaceLabel: String?) {
        let trimmedAccountID = workspaceAccountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = workspaceLabel?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.workspaceAccountID = trimmedAccountID?.isEmpty == false ? trimmedAccountID : nil
        self.workspaceLabel = trimmedLabel?.isEmpty == false ? trimmedLabel : nil
    }

    var isMeaningful: Bool {
        workspaceAccountID != nil || workspaceLabel != nil
    }
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
                stableAccountID: nil,
                authPrincipalIdentity: nil,
                workspaceIdentity: nil,
                snapshotFingerprint: nil,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
    }

    var resolvedRemoteIdentity: CodexRemoteAccountIdentity? {
        identity.remoteIdentity ?? CodexRemoteAccountIdentity(emailAddress: email)
    }

    var lastRemoteRefreshAt: Date {
        if let fetchedAt = rateLimits?.fetchedAt {
            return max(updatedAt, fetchedAt)
        }
        return updatedAt
    }

    var effectivePlanType: String? {
        effectiveCodexPlanType(
            accountPlanType: planType,
            rateLimitPlanType: rateLimits?.planType
        )
    }

    mutating func applyRemoteMetadata(
        email: String?,
        planType: String?,
        rateLimits: CodexRateLimitSnapshot?,
        preferRateLimitPlan: Bool = true
    ) {
        self.email = email
        self.planType = effectiveCodexPlanType(
            accountPlanType: planType,
            rateLimitPlanType: preferRateLimitPlan ? rateLimits?.planType : nil
        )
        self.rateLimits = rateLimits
        identity.remoteIdentity = CodexRemoteAccountIdentity(emailAddress: email)
    }
}
