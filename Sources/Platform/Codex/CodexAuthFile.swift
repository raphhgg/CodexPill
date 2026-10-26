import CryptoKit
import Foundation
import OSLog

private let codexAuthFileLogger = Logger(subsystem: "com.raphhgg.rusage", category: "CodexAuthFile")

/// `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`): the one Codex sign-in on this Mac, which rusage reads and, when
/// the user signs in to another account, replaces.
struct CodexAuthFile: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func read() throws -> Data {
        try Data(contentsOf: url)
    }

    /// The fingerprint of the sign-in now, or nil when there is none.
    func currentFingerprint() -> String? {
        (try? read()).map(Self.fingerprint)
    }

    /// The account the sign-in now names, without a reading, or nil when Codex is signed out.
    func currentAccount() -> CodexAccount? {
        (try? read()).map { Self.account(forAuthData: $0) }
    }

    func write(_ authData: Data) throws {
        codexAuthFileLogger.log("Replacing the Codex sign-in")
        try authData.write(to: url, options: .atomic)
        try FilePermissionHardening.repairPrivateFile(at: url)
    }

    /// Signs Codex out on this Mac, the app and the CLI alike.
    func remove() throws {
        codexAuthFileLogger.log("Removing the Codex sign-in")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// The account `authData` signs in to, read from its tokens, without a reading.
    static func account(forAuthData authData: Data, id: UUID = UUID()) -> CodexAccount {
        CodexAccount(
            id: id,
            email: CodexAuthDataParser.email(from: authData),
            planType: CodexAuthDataParser.planType(from: authData),
            usage: nil,
            identity: CodexAccountIdentity(
                stableAccountID: CodexAuthDataParser.stableAccountID(from: authData),
                authPrincipalIdentity: CodexAuthDataParser.authPrincipalIdentity(from: authData),
                workspaceIdentity: CodexAuthDataParser.workspaceIdentity(from: authData),
                snapshotFingerprint: fingerprint(authData),
                remoteIdentity: CodexAuthDataParser.remoteIdentity(from: authData)
            )
        )
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
