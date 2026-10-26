import Foundation
import Testing

@testable import RUsage

struct CodexAuthFileTests {
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

        let identity = CodexAuthDataParser.authPrincipalIdentity(from: authData)

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

        let identity = CodexAuthDataParser.workspaceIdentity(from: authData)

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

        #expect(CodexAuthDataParser.workspaceIdentity(from: authData) == nil)
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

        let identity = CodexAuthDataParser.workspaceIdentity(from: authData)

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
    func theAccountReadsFromTheSignInWithoutAReading() throws {
        let authData = try makeAuthData(idTokenPayload: [
            "email": "person@example.com",
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-123", "chatgpt_plan_type": "plus"],
        ])

        let account = CodexAuthFile.account(forAuthData: authData)

        #expect(account.email == "person@example.com")
        #expect(account.planType == "plus")
        #expect(account.usage == nil)
        #expect(account.identity.snapshotFingerprint == CodexAuthFile.fingerprint(authData))
    }

    @Test
    func writingTheSignInKeepsItPrivate() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = CodexAuthFile(url: root.appendingPathComponent("auth.json"))
        try Data("old auth".utf8).write(to: file.url)
        try setPosixPermissions(0o644, at: file.url)

        try file.write(Data("new auth".utf8))

        #expect(try file.read() == Data("new auth".utf8))
        #expect(try posixPermissions(at: file.url) == 0o600)
    }

    @Test
    func aMissingSignInIsSignedOut() {
        let file = CodexAuthFile(url: temporaryDirectory().appendingPathComponent("auth.json"))

        #expect(file.currentAccount() == nil)
        #expect(file.currentFingerprint() == nil)
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

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        return try #require(value as? Int) & 0o777
    }

    private func setPosixPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}
