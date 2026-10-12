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

struct CodexAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var snapshotFileName: String
    var createdAt: Date
    var updatedAt: Date
    var email: String?
    var planType: String?
    var usage: UsageSnapshot?
    var identity: CodexAccountIdentity

    init(
        id: UUID,
        snapshotFileName: String,
        createdAt: Date,
        updatedAt: Date,
        email: String?,
        planType: String?,
        usage: UsageSnapshot?,
        identity: CodexAccountIdentity = .empty
    ) {
        self.id = id
        self.snapshotFileName = snapshotFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.email = email
        self.planType = planType
        self.usage = usage
        self.identity = identity
    }

    private enum CodingKeys: String, CodingKey {
        case id
        /// The name users once typed for an account. It is no longer read, but is still written, as the email, so
        /// earlier app versions, which require it, can read the file.
        case legacyName = "name"
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
        snapshotFileName = try container.decode(String.self, forKey: .snapshotFileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        usage = try container.decodeIfPresent(StoredCodexRateLimits.self, forKey: .rateLimits)?.usage
        identity = try container.decodeIfPresent(CodexAccountIdentity.self, forKey: .identity)
            ?? CodexAccountIdentity(
                stableAccountID: nil,
                authPrincipalIdentity: nil,
                workspaceIdentity: nil,
                snapshotFingerprint: nil,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email ?? "Codex account", forKey: .legacyName)
        try container.encode(snapshotFileName, forKey: .snapshotFileName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(planType, forKey: .planType)
        try container.encodeIfPresent(usage.map(StoredCodexRateLimits.init), forKey: .rateLimits)
        try container.encode(identity, forKey: .identity)
    }

    /// Saved accounts list by email, then the ones without an email in the order they were added.
    static func listOrder(_ lhs: CodexAccount, _ rhs: CodexAccount) -> Bool {
        switch (lhs.email, rhs.email) {
        case let (left?, right?) where left.caseInsensitiveCompare(right) != .orderedSame:
            left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        case (_?, nil):
            true
        case (nil, _?):
            false
        default:
            lhs.createdAt < rhs.createdAt
        }
    }

    var resolvedRemoteIdentity: CodexRemoteAccountIdentity? {
        identity.remoteIdentity ?? CodexRemoteAccountIdentity(emailAddress: email)
    }

    var lastRemoteRefreshAt: Date {
        if let fetchedAt = usage?.fetchedAt {
            return max(updatedAt, fetchedAt)
        }
        return updatedAt
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
}

/// The `rateLimits` shape that accounts.json has always stored: Codex's positional primary and
/// secondary windows. Writing the same shape keeps the file readable by earlier app versions.
/// Reading names each window by its length again, so a file saved with the wrong names reads correctly.
private struct StoredCodexRateLimits: Codable {
    struct Window: Codable {
        var usedPercent: Int
        var resetsAt: Date?
        var windowDurationMinutes: Int?
    }

    struct ResetCredits: Codable {
        struct Credit: Codable {
            var expiresAt: Date?
        }

        var availableCount: Int
        var credits: [Credit]?
    }

    var planType: String?
    var primary: Window?
    var secondary: Window?
    var fetchedAt: Date
    var resetCredits: ResetCredits?

    init(_ usage: UsageSnapshot) {
        planType = usage.planName
        primary = usage.codexSlots.primary.map(Window.init)
        secondary = usage.codexSlots.secondary.map(Window.init)
        fetchedAt = usage.fetchedAt
        resetCredits = usage.resetCredits.map { resetCredits in
            ResetCredits(
                availableCount: resetCredits.availableCount,
                credits: resetCredits.credits?.map { ResetCredits.Credit(expiresAt: $0.expiresAt) }
            )
        }
    }

    var usage: UsageSnapshot {
        var usage = UsageSnapshot.codex(
            planName: planType,
            primary: primary.map { ($0.usedPercent, $0.resetsAt, $0.windowDurationMinutes) },
            secondary: secondary.map { ($0.usedPercent, $0.resetsAt, $0.windowDurationMinutes) },
            fetchedAt: fetchedAt
        )
        usage.resetCredits = resetCredits.map { resetCredits in
            UsageResetCredits(
                availableCount: resetCredits.availableCount,
                credits: resetCredits.credits?.map { UsageResetCredit(expiresAt: $0.expiresAt) }
            )
        }
        return usage
    }
}

private extension StoredCodexRateLimits.Window {
    init(_ window: UsageWindow) {
        self.init(
            usedPercent: window.usedPercent,
            resetsAt: window.resetsAt,
            windowDurationMinutes: window.durationMinutes
        )
    }
}
