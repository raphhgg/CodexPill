import Foundation

extension CodexAccount {
    func matchesSameAccount(as other: CodexAccount) -> Bool {
        id == other.id ||
            hasSameStrongAccountIdentity(as: other) ||
            hasSameDisplayAccountIdentity(as: other)
    }

    private func hasSameStrongAccountIdentity(as other: CodexAccount) -> Bool {
        if let stableAccountID = normalizedIdentityValue(identity.stableAccountID),
           stableAccountID == normalizedIdentityValue(other.identity.stableAccountID) {
            return true
        }

        if let snapshotFingerprint = normalizedIdentityValue(identity.snapshotFingerprint),
           snapshotFingerprint == normalizedIdentityValue(other.identity.snapshotFingerprint) {
            return true
        }

        if let authPrincipalIdentity = identity.authPrincipalIdentity,
           authPrincipalIdentity.isMeaningful,
           authPrincipalIdentity == other.identity.authPrincipalIdentity {
            return true
        }

        if let workspaceIdentity = identity.workspaceIdentity,
           workspaceIdentity.isMeaningful,
           workspaceIdentity == other.identity.workspaceIdentity {
            return true
        }

        return false
    }

    private func hasSameDisplayAccountIdentity(as other: CodexAccount) -> Bool {
        normalizedInspectableEmail != nil
            && normalizedInspectableEmail == other.normalizedInspectableEmail
            && normalizedCodexPlanType(effectivePlanType) == normalizedCodexPlanType(other.effectivePlanType)
            && normalizedAccountName == other.normalizedAccountName
    }

    private var normalizedInspectableEmail: String? {
        guard let email else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private var normalizedAccountName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedIdentityValue(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}
