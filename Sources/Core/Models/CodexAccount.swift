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

    /// The ChatGPT user ID decides when both have one. The subject also names how the user signed in, such as
    /// `google-oauth2|…`, so it changes when the same user signs in another way.
    func isSameUser(as other: CodexAuthPrincipalIdentity?) -> Bool {
        guard let other else { return false }
        if let chatGPTUserID, let otherChatGPTUserID = other.chatGPTUserID {
            return chatGPTUserID == otherChatGPTUserID
        }
        return self == other
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

/// The Codex account `~/.codex/auth.json` signs in to, with its last reading. rusage keeps no other Codex account.
struct CodexAccount: Identifiable, Hashable {
    let id: UUID
    var email: String?
    var planType: String?
    var usage: UsageSnapshot?
    var identity: CodexAccountIdentity

    init(
        id: UUID = UUID(),
        email: String?,
        planType: String?,
        usage: UsageSnapshot?,
        identity: CodexAccountIdentity = .empty
    ) {
        self.id = id
        self.email = email
        self.planType = planType
        self.usage = usage
        self.identity = identity
    }

    var effectivePlanType: String? {
        effectiveCodexPlanType(
            accountPlanType: planType,
            rateLimitPlanType: usage?.planName
        )
    }

    mutating func applyRemoteMetadata(
        email: String?,
        planType: String?,
        usage: UsageSnapshot?,
        preferRateLimitPlan: Bool = true
    ) {
        self.email = email
        self.planType = effectiveCodexPlanType(
            accountPlanType: planType,
            rateLimitPlanType: preferRateLimitPlan ? usage?.planName : nil
        )
        self.usage = usage
        identity.remoteIdentity = CodexRemoteAccountIdentity(emailAddress: email)
    }

    /// Whether `other` is the same Codex user and workspace, as when a sign-in returns the account already in use.
    func isSameAccount(as other: CodexAccount) -> Bool {
        if let stableAccountID = identity.stableAccountID, stableAccountID == other.identity.stableAccountID {
            return identity.authPrincipalIdentity.map { $0.isSameUser(as: other.identity.authPrincipalIdentity) } ?? true
        }
        return identity.snapshotFingerprint != nil && identity.snapshotFingerprint == other.identity.snapshotFingerprint
    }
}
