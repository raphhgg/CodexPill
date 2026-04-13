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
}
