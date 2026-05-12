import Foundation
import Testing

@testable import CodexPill

struct CodexAuthSnapshotServiceTests {
    @Test
    func authPrincipalIdentityParsesSubjectAndChatGPTUserIDFromIDToken() throws {
        let payload: [String: Any] = [
            "sub": "auth0|principal-123",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct-123",
                "chatgpt_user_id": "user-123",
            ],
        ]
        let authData = try makeAuthData(idTokenPayload: payload)

        let identity = CodexAuthSnapshotService.authPrincipalIdentity(for: authData)

        #expect(identity == CodexAuthPrincipalIdentity(
            subject: "auth0|principal-123",
            chatGPTUserID: "user-123"
        ))
    }

    @Test
    func workspaceIdentityParsesDefaultOrganizationFromIDToken() throws {
        let payload: [String: Any] = [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct-123",
                "organizations": [
                    [
                        "id": "org-secondary",
                        "title": "Secondary",
                        "is_default": false,
                    ],
                    [
                        "id": "org-team",
                        "title": "Team",
                        "is_default": true,
                    ],
                ],
            ],
        ]
        let authData = try makeAuthData(idTokenPayload: payload)

        let identity = CodexAuthSnapshotService.workspaceIdentity(for: authData)

        #expect(identity == CodexWorkspaceIdentity(
            workspaceAccountID: "org-team",
            workspaceLabel: "Team"
        ))
    }

    @Test
    func workspaceIdentityReturnsNilWhenOrganizationsAreMissing() throws {
        let payload: [String: Any] = [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct-123",
            ],
        ]
        let authData = try makeAuthData(idTokenPayload: payload)

        #expect(CodexAuthSnapshotService.workspaceIdentity(for: authData) == nil)
    }

    @Test
    func workspaceIdentityFallsBackToTopLevelOrganizationsClaim() throws {
        let payload: [String: Any] = [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct-123",
            ],
            "https://api.openai.com/organizations": [
                [
                    "id": "org-secondary",
                    "title": "Secondary",
                    "is_default": false,
                ],
                [
                    "id": "org-team",
                    "title": "Team",
                    "is_default": true,
                ],
            ],
        ]
        let authData = try makeAuthData(idTokenPayload: payload)

        let identity = CodexAuthSnapshotService.workspaceIdentity(for: authData)

        #expect(identity == CodexWorkspaceIdentity(
            workspaceAccountID: "org-team",
            workspaceLabel: "Team"
        ))
    }

    @Test
    func parserReadsEmailAndPlanTypeFromIDToken() throws {
        let payload: [String: Any] = [
            "email": "person@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct-123",
                "chatgpt_plan_type": "team",
            ],
        ]
        let authData = try makeAuthData(idTokenPayload: payload)

        #expect(CodexAuthDataParser.email(from: authData) == "person@example.com")
        #expect(CodexAuthDataParser.planType(from: authData) == "team")
        #expect(CodexAuthDataParser.remoteIdentity(from: authData) == CodexRemoteAccountIdentity(emailAddress: "person@example.com"))
    }

    @Test
    func activateRepairsCurrentAuthFilePermissions() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeRepository(root: root)
        let service = CodexAuthSnapshotService(repository: repository)
        let account = makeAccount()
        try repository.bootstrapStorage()
        try repository.writeSnapshot(data: Data("saved auth".utf8), for: account)

        try service.activate(account)

        #expect(try posixPermissions(at: repository.paths.codexAuthFile) == 0o600)
    }

    @Test
    func restoreCurrentAuthDataRepairsPermissiveCurrentAuthFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeRepository(root: root)
        let service = CodexAuthSnapshotService(repository: repository)
        try repository.bootstrapStorage()
        try Data("old auth".utf8).write(to: repository.paths.codexAuthFile)
        try setPosixPermissions(0o644, at: repository.paths.codexAuthFile)

        try service.restoreCurrentAuthData(Data("restored auth".utf8))

        #expect(try posixPermissions(at: repository.paths.codexAuthFile) == 0o600)
    }

    private func makeAuthData(idTokenPayload: [String: Any]) throws -> Data {
        let header = try makeJWTPart(["alg": "none", "typ": "JWT"])
        let payload = try makeJWTPart(idTokenPayload)
        let token = "\(header).\(payload).signature"
        let auth: [String: Any] = [
            "tokens": [
                "account_id": "acct-123",
                "id_token": token,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: auth)
    }

    private func makeJWTPart(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeRepository(root: URL) throws -> AccountRepository {
        try AccountRepository(
            fileManager: .default,
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: root.path]
        )
    }

    private func makeAccount() -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: "Research",
            snapshotFileName: "research.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: .empty
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        return try #require(value as? Int) & 0o777
    }

    private func setPosixPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}
