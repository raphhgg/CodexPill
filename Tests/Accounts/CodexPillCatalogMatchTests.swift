import Foundation
import Testing

@testable import RUsage

/// A CodexPill catalog copied to rusage must still find the account Codex is signed in to.
@MainActor
struct CodexPillCatalogMatchTests {
    /// The live sign-in is newer than the saved snapshot, and may come from another sign-in method.
    @Test(arguments: ["auth0|pro-subject", "google-oauth2|pro-subject"])
    func copiedCodexPillCatalogFindsTheAccountInUse(liveSubject: String) throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let savedAuth = try makeAuthData(accessToken: "saved", subject: "auth0|pro-subject")
        try fixture.writeCodexPill(catalog: oldCatalog(identityFrom: savedAuth), snapshot: savedAuth)

        #expect(fixture.migration().run() == .copied)
        try fixture.writeLiveAuth(makeAuthData(accessToken: "refreshed", subject: liveSubject))
        let controller = try fixture.loadController()

        #expect(controller.accounts.map(\.email) == ["pro@example.com"])
        #expect(controller.activeAccount?.id == Self.accountID)
        let card = MenuBarMenuState(activeAccount: controller.activeAccount, inactiveAccounts: controller.inactiveAccounts)
            .toolSections.first { $0.provider == .codex }?.card
        #expect(card?.title == nil)
        #expect(card?.windows.map(\.usedPercent) == [40])
    }

    private static let accountID = UUID(uuidString: "6F1D2C3B-4A59-4E6F-8A7B-9C0D1E2F3A4B")!

    private func oldCatalog(identityFrom authData: Data) throws -> Data {
        let principal = try #require(CodexAuthDataParser.authPrincipalIdentity(from: authData))
        let workspace = try #require(CodexAuthDataParser.workspaceIdentity(from: authData))
        let account: [String: Any] = [
            "id": Self.accountID.uuidString,
            "name": "Pro",
            "snapshotFileName": "\(Self.accountID.uuidString).json",
            "createdAt": "2026-05-01T09:00:00Z",
            "updatedAt": "2026-10-10T09:00:00Z",
            "email": "pro@example.com",
            "planType": "pro",
            "rateLimits": [
                "limitID": "codex",
                "planType": "pro",
                "primary": ["usedPercent": 12, "resetsAt": "2026-10-12T14:00:00Z", "windowDurationMinutes": 300],
                "secondary": ["usedPercent": 40, "resetsAt": "2026-10-15T09:00:00Z", "windowDurationMinutes": 10080],
                "fetchedAt": "2026-10-12T09:00:00Z",
            ],
            "identity": [
                "stableAccountID": "acct-pro",
                "authPrincipalIdentity": ["subject": principal.subject, "chatGPTUserID": principal.chatGPTUserID],
                "workspaceIdentity": ["workspaceAccountID": workspace.workspaceAccountID, "workspaceLabel": workspace.workspaceLabel],
                "snapshotFingerprint": CodexAuthSnapshotService.snapshotFingerprint(for: authData),
                "remoteIdentity": ["normalizedEmailAddress": "pro@example.com"],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: [account], options: [.prettyPrinted, .sortedKeys])
    }

    private func makeAuthData(accessToken: String, subject: String) throws -> Data {
        let payload: [String: Any] = [
            "sub": subject,
            "email": "pro@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct-pro",
                "chatgpt_user_id": "user-pro",
                "chatgpt_plan_type": "pro",
                "organizations": [["id": "org-pro", "title": "Personal", "is_default": true]],
            ],
        ]
        let idToken = try ["{\"alg\":\"none\"}", String(decoding: JSONSerialization.data(withJSONObject: payload), as: UTF8.self)]
            .map { Data($0.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") }
            .joined(separator: ".") + ".signature"
        let auth: [String: Any] = [
            "OPENAI_API_KEY": NSNull(),
            "tokens": ["account_id": "acct-pro", "id_token": idToken, "access_token": accessToken],
        ]
        return try JSONSerialization.data(withJSONObject: auth)
    }
}

@MainActor
private struct CatalogFixture {
    let root: URL
    let suiteName = "CodexPillCatalogMatchTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    var codexPillFolder: URL { root.appendingPathComponent("CodexPill", isDirectory: true) }
    var rusageFolder: URL { root.appendingPathComponent("rusage", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPillCatalogMatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func writeCodexPill(catalog: Data, snapshot: Data) throws {
        let snapshots = codexPillFolder.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try catalog.write(to: codexPillFolder.appendingPathComponent("accounts.json"))
        let account = try #require((try JSONSerialization.jsonObject(with: catalog) as? [[String: Any]])?.first)
        try snapshot.write(to: snapshots.appendingPathComponent(try #require(account["snapshotFileName"] as? String)))
    }

    /// The isolated root holds Codex's auth.json too, so rusage's folder doubles as CODEX_HOME.
    func writeLiveAuth(_ data: Data) throws {
        try data.write(to: rusageFolder.appendingPathComponent("auth.json"))
    }

    func migration() -> CodexPillMigration {
        CodexPillMigration(
            legacy: CodexPillLegacyData(folder: codexPillFolder, preferences: [:]),
            folder: rusageFolder,
            defaults: defaults,
            defaultsDomain: suiteName
        )
    }

    func loadController() throws -> AccountsController {
        let repository = try AccountRepository(isolatedRootDirectory: rusageFolder)
        let controller = AccountsFeatureFactory(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: CodexAppProcessProbe(),
            accountStatusClient: DisabledAccountStatusClient()
        ).makeController()
        controller.load()
        return controller
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
