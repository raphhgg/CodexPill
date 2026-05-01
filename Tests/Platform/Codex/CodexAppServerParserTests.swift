import Foundation
import Testing

@testable import CodexPill

struct CodexAppServerParserTests {
    @Test
    func accountParserMapsIdentityPayloadsIntoGenericDTO() throws {
        let response = try decodeAccountResponse("""
        {
          "account": {
            "email": "user@example.com",
            "planType": "team",
            "stableAccountID": "stable-account",
            "authPrincipalIdentity": {
              "subject": "principal-subject",
              "chatGPTUserID": "chatgpt-user"
            },
            "workspaceIdentity": {
              "workspaceAccountID": "workspace-account",
              "workspaceLabel": "workspace-label"
            },
            "snapshotFingerprint": "snapshot-fingerprint"
          }
        }
        """)

        let account = try #require(CodexAppServerAccountParser().parse(response))

        #expect(account.email == "user@example.com")
        #expect(account.planType == "team")
        #expect(account.stableAccountID == "stable-account")
        #expect(account.authPrincipalIdentity?.subject == "principal-subject")
        #expect(account.authPrincipalIdentity?.chatGPTUserID == "chatgpt-user")
        #expect(account.workspaceIdentity?.workspaceAccountID == "workspace-account")
        #expect(account.workspaceIdentity?.workspaceLabel == "workspace-label")
        #expect(account.snapshotFingerprint == "snapshot-fingerprint")
    }

    @Test
    func rateLimitParserPrefersCompleteCodexLimitByIDOverLegacyFallback() throws {
        let response = try decodeRateLimitsResponse("""
        {
          "rateLimits": {
            "limitId": "fallback",
            "planType": "team",
            "primary": { "usedPercent": 90, "resetsAt": 2000000000, "windowDurationMins": 300 },
            "secondary": { "usedPercent": 80, "resetsAt": 2000500000, "windowDurationMins": 10080 }
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": "Codex",
              "planType": "team",
              "primary": { "usedPercent": 21, "resetsAt": 2000000000, "windowDurationMins": 300 },
              "secondary": { "usedPercent": 34, "resetsAt": 2000500000, "windowDurationMins": 10080 }
            }
          }
        }
        """)

        let rateLimits = try #require(CodexAppServerRateLimitParser().parse(
            response,
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_100)
        ))

        #expect(rateLimits.limitID == "codex")
        #expect(rateLimits.limitName == "Codex")
        #expect(rateLimits.primary?.usedPercent == 21)
        #expect(rateLimits.secondary?.usedPercent == 34)
        #expect(rateLimits.fetchedAt == Date(timeIntervalSince1970: 2_000_000_100))
    }

    @Test
    func rateLimitParserUsesLegacyRateLimitsWhenCodexLimitIsMissing() throws {
        let response = try decodeRateLimitsResponse("""
        {
          "rateLimits": {
            "limitId": "legacy",
            "planType": "plus",
            "primary": { "usedPercent": 42, "resetsAt": 2000000000, "windowDurationMins": 300 },
            "secondary": { "usedPercent": 18, "resetsAt": 2000500000, "windowDurationMins": 10080 }
          },
          "rateLimitsByLimitId": {
            "other": {
              "limitId": "other",
              "primary": { "usedPercent": 1 },
              "secondary": { "usedPercent": 2 }
            }
          }
        }
        """)

        let rateLimits = try #require(CodexAppServerRateLimitParser().parse(response))

        #expect(rateLimits.limitID == "legacy")
        #expect(rateLimits.planType == "plus")
        #expect(rateLimits.primary?.usedPercent == 42)
        #expect(rateLimits.secondary?.usedPercent == 18)
    }

    @Test
    func rateLimitParserUsesLegacyRateLimitsWhenCodexLimitIsPartial() throws {
        let response = try decodeRateLimitsResponse("""
        {
          "rateLimits": {
            "limitId": "legacy",
            "primary": { "usedPercent": 42 },
            "secondary": { "usedPercent": 18 }
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "primary": { "usedPercent": 21 }
            }
          }
        }
        """)

        let rateLimits = try #require(CodexAppServerRateLimitParser().parse(response))

        #expect(rateLimits.limitID == "legacy")
        #expect(rateLimits.primary?.usedPercent == 42)
        #expect(rateLimits.secondary?.usedPercent == 18)
    }

    @Test
    func rateLimitParserDropsInvalidWindowsWithoutFailing() throws {
        let response = try decodeRateLimitsResponse("""
        {
          "rateLimits": {
            "limitId": "legacy",
            "primary": { "resetsAt": 2000000000, "windowDurationMins": 300 },
            "secondary": { "usedPercent": 18, "resetsAt": 2000500000, "windowDurationMins": 10080 }
          }
        }
        """)

        let rateLimits = try #require(CodexAppServerRateLimitParser().parse(response))

        #expect(rateLimits.primary == nil)
        #expect(rateLimits.secondary?.usedPercent == 18)
    }

    @Test
    func rateLimitParserReturnsNilWhenPayloadContainsNoUsableRateLimits() throws {
        let response = try decodeRateLimitsResponse(#"{}"#)

        #expect(CodexAppServerRateLimitParser().parse(response) == nil)
    }

    @Test
    func codexPillMapperConvertsGenericDTOsIntoAccountStatusAndSnapshot() {
        let mapper = CodexPillAccountStatusMapper()
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_100)
        let status = mapper.status(from: CodexAppServerStatus(
            account: CodexAppServerAccount(
                email: "user@example.com",
                planType: "team",
                stableAccountID: "stable-account",
                authPrincipalIdentity: nil,
                workspaceIdentity: nil,
                snapshotFingerprint: "snapshot-fingerprint"
            ),
            rateLimits: CodexAppServerRateLimits(
                limitID: "codex",
                limitName: "Codex",
                planType: "team",
                primary: CodexAppServerRateLimitWindow(
                    usedPercent: 12,
                    resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
                    windowDurationMinutes: 300
                ),
                secondary: CodexAppServerRateLimitWindow(
                    usedPercent: 32,
                    resetsAt: Date(timeIntervalSince1970: 2_000_500_000),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: fetchedAt
            )
        ))

        #expect(status.email == "user@example.com")
        #expect(status.planType == "team")
        #expect(status.stableAccountID == "stable-account")
        #expect(status.snapshotFingerprint == "snapshot-fingerprint")
        #expect(status.rateLimits?.limitID == "codex")
        #expect(status.rateLimits?.limitName == "Codex")
        #expect(status.rateLimits?.primary?.usedPercent == 12)
        #expect(status.rateLimits?.secondary?.windowDurationMinutes == 10_080)
        #expect(status.rateLimits?.fetchedAt == fetchedAt)
    }

    private func decodeAccountResponse(_ json: String) throws -> AppServerAccountResponse {
        try JSONDecoder().decode(AppServerAccountResponse.self, from: Data(json.utf8))
    }

    private func decodeRateLimitsResponse(_ json: String) throws -> AppServerRateLimitsResponse {
        try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: Data(json.utf8))
    }
}
