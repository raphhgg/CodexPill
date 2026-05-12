import Foundation
import Testing

@testable import CodexPill

struct DiagnosticReportBuilderTests {
    @Test
    func exportCopyUsesDiagnosticsProductLanguage() {
        let copy = DiagnosticReportExportCopy()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(copy.panelTitle == "Export Diagnostics")
        #expect(copy.panelPrompt == "Export")
        #expect(copy.defaultFilename(for: date) == "CodexPill-Diagnostics-20270115-080000.json")
    }

    @Test
    func reportAliasesSensitiveAccountAndHostTopologyWithoutRawIdentifiers() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let active = makeAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Work Account",
            email: "person@example.com",
            stableAccountID: "acct_stable_secret",
            fetchedAt: now.addingTimeInterval(-120)
        )
        let inactive = makeAccount(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Personal Account",
            email: "me@example.org",
            stableAccountID: "acct_other_secret",
            fetchedAt: now.addingTimeInterval(-3600)
        )
        let state = makeMenuState(
            activeAccount: active,
            inactiveAccounts: [inactive],
            remoteHosts: [
                RemoteHostMenuState(
                    name: "buildbox",
                    destination: "deploy@buildbox.example.com",
                    connectionState: .connected,
                    desiredAccount: active,
                    activeAccount: active,
                    verificationStatus: .verified,
                    deployedAccountIDs: [active.id]
                )
            ]
        )

        let report = DiagnosticReportBuilder(
            appMetadata: .fixture,
            systemMetadata: .fixture(now: now)
        ).makeReport(
            state: state,
            events: [
                DiagnosticWorkflowEvent(
                    name: "switch_account",
                    category: .switchAccount,
                    occurredAt: now,
                    fields: [
                        .account(active.id, redaction: .accountAlias),
                        .hostDestination("deploy@buildbox.example.com", redaction: .hostAlias)
                    ]
                )
            ]
        )
        let json = try encodedJSONString(report)

        #expect(report.accounts.map(\.alias) == ["account-1", "account-2"])
        #expect(report.hosts.map(\.alias) == ["host-1"])
        #expect(report.hosts.first?.activeAccountAlias == "account-1")
        #expect(report.events.first?.fields["account"] == "account-1")
        #expect(report.events.first?.fields["host"] == "host-1")
        #expect(!json.contains("person@example.com"))
        #expect(!json.contains("me@example.org"))
        #expect(!json.contains("acct_stable_secret"))
        #expect(!json.contains("deploy@buildbox.example.com"))
        #expect(!json.contains("buildbox"))
        #expect(!json.contains(active.id.uuidString))
    }

    @Test
    func eventFieldsWithoutRedactionClassAreDeniedByDefault() throws {
        let accountID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let report = DiagnosticReportBuilder(
            appMetadata: .fixture,
            systemMetadata: .fixture()
        ).makeReport(
            state: makeMenuState(activeAccount: makeAccount(id: accountID), inactiveAccounts: []),
            events: [
                DiagnosticWorkflowEvent(
                    name: "raw_failure",
                    category: .failure,
                    fields: [
                        .string(name: "stderr", value: "Permission denied for /Users/raphh/.codex/auth.json", redaction: nil),
                        .string(name: "reason", value: "host_disconnected", redaction: .reasonCode)
                    ]
                )
            ]
        )
        let json = try encodedJSONString(report)

        #expect(report.events.first?.fields["reason"] == "host_disconnected")
        #expect(report.events.first?.fields["stderr"] == nil)
        #expect(report.redactionManifest.rejectedFields.contains("events.raw_failure.stderr"))
        #expect(!json.contains("/Users/raphh"))
        #expect(!json.contains("Permission denied"))
    }

    @Test
    func tokenLikeAuthLikePathHostAndStableIDValuesAreNotEncoded() throws {
        let rawValues = [
            "sk-proj-abcdefghijklmnopqrstuvwxyz1234567890",
            #"{"access_token":"secret","refresh_token":"secret"}"#,
            "ssh: Could not resolve hostname private.example.com",
            "/Users/raphh/Library/Application Support/Codex/auth.json",
            "acct_stable_secret"
        ]

        let account = makeAccount(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: rawValues.joined(separator: " "),
            email: "secret@example.com",
            stableAccountID: rawValues.last
        )
        let report = DiagnosticReportBuilder(
            appMetadata: .fixture,
            systemMetadata: .fixture()
        ).makeReport(
            state: makeMenuState(
                activeAccount: account,
                inactiveAccounts: [],
                remoteHosts: [
                    RemoteHostMenuState(
                        name: "private.example.com",
                        destination: "user@private.example.com",
                        connectionState: .disconnected,
                        activeAccount: nil,
                        verificationStatus: .failed,
                        lastVerificationError: rawValues[2]
                    )
                ]
            ),
            events: []
        )
        let json = try encodedJSONString(report)

        for rawValue in rawValues {
            #expect(!json.contains(rawValue))
        }
        #expect(!json.contains("secret@example.com"))
        #expect(!json.contains("private.example.com"))
        #expect(report.decisionTraces.contains(where: { $0.reasonCode == "host_disconnected" }))
        #expect(report.decisionTraces.contains(where: { $0.reasonCode == "host_verification_failed" }))
    }

    @Test
    func aliasesAreStableWithinOneExportButDependOnlyOnExportLocalEncounterOrder() {
        let firstID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let secondID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let builder = DiagnosticReportBuilder(appMetadata: .fixture, systemMetadata: .fixture())

        let firstReport = builder.makeReport(
            state: makeMenuState(
                activeAccount: makeAccount(id: firstID),
                inactiveAccounts: [makeAccount(id: secondID)]
            ),
            events: [
                DiagnosticWorkflowEvent(
                    name: "switch_account",
                    category: .switchAccount,
                    fields: [.account(firstID, redaction: .accountAlias)]
                )
            ]
        )
        let secondReport = builder.makeReport(
            state: makeMenuState(
                activeAccount: makeAccount(id: secondID),
                inactiveAccounts: [makeAccount(id: firstID)]
            ),
            events: [
                DiagnosticWorkflowEvent(
                    name: "switch_account",
                    category: .switchAccount,
                    fields: [.account(firstID, redaction: .accountAlias)]
                )
            ]
        )

        #expect(firstReport.events.first?.fields["account"] == "account-1")
        #expect(secondReport.events.first?.fields["account"] == "account-2")
        #expect(firstReport.redactionManifest.aliasScope == "per-export")
    }
}

private extension DiagnosticAppMetadata {
    static let fixture = DiagnosticAppMetadata(
        appVersion: "1.0",
        buildNumber: "1",
        bundleIdentifier: "com.raphhgg.codexpill"
    )
}

private extension DiagnosticSystemMetadata {
    static func fixture(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> DiagnosticSystemMetadata {
        DiagnosticSystemMetadata(
            macOSVersion: "14.0",
            exportTimestamp: now,
            localeIdentifier: "en_US",
            timeZoneIdentifier: "UTC",
            architecture: "arm64",
            isSandboxed: false
        )
    }
}

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

private func makeMenuState(
    activeAccount: CodexAccount?,
    inactiveAccounts: [CodexAccount],
    remoteHosts: [RemoteHostMenuState] = []
) -> MenuBarMenuState {
    MenuBarMenuState(
        activeAccount: activeAccount,
        inactiveAccounts: inactiveAccounts,
        remoteHosts: remoteHosts,
        visibleInactiveAccountCount: 5,
        visibleInactiveAccountCountOptions: [3, 5],
        refreshIntervalMinutes: 5,
        refreshIntervalOptions: [5, 15],
        statusBarMonochrome: false,
        statusBarIndicatorStyle: .stackedBars,
        statusBarDisplayMode: .iconOnly,
        isBusy: false,
        statusMessage: ""
    )
}

private func makeAccount(
    id: UUID = UUID(),
    name: String = "Account",
    email: String? = nil,
    stableAccountID: String? = nil,
    fetchedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> CodexAccount {
    CodexAccount(
        id: id,
        name: name,
        snapshotFileName: "snapshot-\(id.uuidString).json",
        createdAt: fetchedAt.addingTimeInterval(-600),
        updatedAt: fetchedAt,
        email: email,
        planType: "plus",
        rateLimits: CodexRateLimitSnapshot(
            limitID: "limit-secret",
            limitName: "Limit Secret",
            planType: "plus",
            primary: CodexRateLimitWindow(usedPercent: 40, resetsAt: fetchedAt.addingTimeInterval(1800), windowDurationMinutes: 300),
            secondary: CodexRateLimitWindow(usedPercent: 70, resetsAt: fetchedAt.addingTimeInterval(86_400), windowDurationMinutes: 10_080),
            fetchedAt: fetchedAt
        ),
        identity: CodexAccountIdentity(stableAccountID: stableAccountID)
    )
}
