import CryptoKit
import Foundation
import OSLog

private let authSnapshotLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "AuthSnapshot")

struct CodexAuthSnapshotService {
    private let repository: AccountRepository

    init(repository: AccountRepository) {
        self.repository = repository
    }

    func readCurrentAuthData() throws -> Data {
        authSnapshotLogger.log("Reading current auth data from \(repository.paths.codexAuthFile.path, privacy: .public)")
        return try Data(contentsOf: repository.paths.codexAuthFile)
    }

    func saveCurrentAuthSnapshot(
        named name: String,
        existing: CodexAccount? = nil
    ) throws -> CodexAccount {
        let authData = try readCurrentAuthData()
        return try saveAuthSnapshot(
            authData,
            named: name,
            existing: existing
        )
    }

    func saveAuthSnapshot(
        _ authData: Data,
        named name: String,
        existing: CodexAccount? = nil
    ) throws -> CodexAccount {
        var account = existing ?? CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: Date(),
            updatedAt: Date(),
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: .empty
        )
        account.name = name
        account.updatedAt = Date()
        account.identity.stableAccountID = Self.stableAccountID(for: authData)
        account.identity.authPrincipalIdentity = Self.authPrincipalIdentity(for: authData)
        account.identity.workspaceIdentity = Self.workspaceIdentity(for: authData)
        account.identity.snapshotFingerprint = Self.snapshotFingerprint(for: authData)
        account.identity.remoteIdentity = CodexAuthDataParser.remoteIdentity(from: authData)
        account.email = CodexAuthDataParser.email(from: authData)
        account.planType = CodexAuthDataParser.planType(from: authData)
        try repository.writeSnapshot(data: authData, for: account)
        return account
    }

    func deleteAuthSnapshot(for account: CodexAccount) throws {
        try repository.deleteSnapshot(for: account)
    }

    func activate(_ account: CodexAccount) throws {
        authSnapshotLogger.log("Activating snapshot for account name: \(account.name, privacy: .public)")
        let snapshot = try repository.readSnapshot(for: account)
        try snapshot.write(to: repository.paths.codexAuthFile, options: .atomic)
    }

    func restoreCurrentAuthData(_ data: Data) throws {
        try data.write(to: repository.paths.codexAuthFile, options: .atomic)
    }

    func prepareForNewSignIn() throws {
        let authFile = repository.paths.codexAuthFile
        let fileManager = FileManager.default

        let exists = fileManager.fileExists(atPath: authFile.path)
        authSnapshotLogger.log("Preparing for new sign-in. Auth file exists: \(exists, privacy: .public)")
        guard exists else { return }
        authSnapshotLogger.log("Removing auth file at \(authFile.path, privacy: .public)")
        try fileManager.removeItem(at: authFile)
        authSnapshotLogger.log("Removed auth file successfully")
    }

    func currentAuthFingerprint() -> String? {
        guard let current = try? Data(contentsOf: repository.paths.codexAuthFile) else {
            return nil
        }
        return Self.snapshotFingerprint(for: current)
    }

    func currentStableAccountID() -> String? {
        guard let current = try? Data(contentsOf: repository.paths.codexAuthFile) else {
            return nil
        }
        return Self.stableAccountID(for: current)
    }

    func currentAuthPrincipalIdentity() -> CodexAuthPrincipalIdentity? {
        guard let current = try? Data(contentsOf: repository.paths.codexAuthFile) else {
            return nil
        }
        return Self.authPrincipalIdentity(for: current)
    }

    func currentWorkspaceIdentity() -> CodexWorkspaceIdentity? {
        guard let current = try? Data(contentsOf: repository.paths.codexAuthFile) else {
            return nil
        }
        return Self.workspaceIdentity(for: current)
    }

    func currentRemoteIdentity() -> CodexRemoteAccountIdentity? {
        guard let current = try? Data(contentsOf: repository.paths.codexAuthFile) else {
            return nil
        }
        return CodexAuthDataParser.remoteIdentity(from: current)
    }

    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: Self.stableAccountID(for: authData),
            authPrincipalIdentity: Self.authPrincipalIdentity(for: authData),
            workspaceIdentity: Self.workspaceIdentity(for: authData),
            snapshotFingerprint: Self.snapshotFingerprint(for: authData),
            remoteIdentity: CodexAuthDataParser.remoteIdentity(from: authData)
        )
    }

    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts.map { account in
            var reconciled = account

            if (
                reconciled.identity.stableAccountID == nil ||
                    reconciled.identity.authPrincipalIdentity == nil ||
                    reconciled.identity.workspaceIdentity == nil ||
                    reconciled.identity.snapshotFingerprint == nil
            ),
               let snapshot = try? repository.readSnapshot(for: account) {
                if reconciled.identity.stableAccountID == nil {
                    reconciled.identity.stableAccountID = Self.stableAccountID(for: snapshot)
                }
                if reconciled.identity.authPrincipalIdentity == nil {
                    reconciled.identity.authPrincipalIdentity = Self.authPrincipalIdentity(for: snapshot)
                }
                if reconciled.identity.workspaceIdentity == nil {
                    reconciled.identity.workspaceIdentity = Self.workspaceIdentity(for: snapshot)
                }
                if reconciled.identity.snapshotFingerprint == nil {
                    reconciled.identity.snapshotFingerprint = Self.snapshotFingerprint(for: snapshot)
                }
            }

            if reconciled.identity.remoteIdentity == nil {
                reconciled.identity.remoteIdentity = CodexRemoteAccountIdentity(emailAddress: reconciled.email)
            }

            return reconciled
        }
    }

    static func snapshotFingerprint(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func stableAccountID(for data: Data) -> String? {
        CodexAuthDataParser.stableAccountID(from: data)
    }

    static func authPrincipalIdentity(for data: Data) -> CodexAuthPrincipalIdentity? {
        CodexAuthDataParser.authPrincipalIdentity(from: data)
    }

    static func workspaceIdentity(for data: Data) -> CodexWorkspaceIdentity? {
        CodexAuthDataParser.workspaceIdentity(from: data)
    }
}
