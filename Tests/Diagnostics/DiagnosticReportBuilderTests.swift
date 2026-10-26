import Foundation
import Testing

@testable import RUsage

struct DiagnosticReportBuilderTests {
    @Test
    func exportCopyUsesDiagnosticsProductLanguage() {
        let copy = DiagnosticReportExportCopy()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(copy.panelTitle == "Export Diagnostics")
        #expect(copy.panelPrompt == "Export")
        #expect(copy.defaultFilename(for: date) == "rusage-Diagnostics-20270115-080000.json")
    }

    @Test
    func reportAliasesSensitiveAccountsWithoutRawIdentifiers() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let active = makeAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            email: "person@example.com",
            stableAccountID: "acct_stable_secret",
            usage: makeUsage(fetchedAt: now.addingTimeInterval(-120))
        )
        let inactive = makeAccount(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            email: "me@example.org",
            stableAccountID: "acct_other_secret",
            usage: makeUsage(fetchedAt: now.addingTimeInterval(-3600))
        )
        let state = makeMenuState(activeAccount: active, inactiveAccounts: [inactive])

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
                    fields: [.account(active.id, redaction: .accountAlias)]
                )
            ]
        )
        let json = try encodedJSONString(report)

        #expect(report.accounts.map(\.alias) == ["account-1", "account-2"])
        #expect(report.events.first?.fields["account"] == "account-1")
        #expect(!json.contains("person@example.com"))
        #expect(!json.contains("me@example.org"))
        #expect(!json.contains("acct_stable_secret"))
        #expect(!json.contains(active.id.uuidString))
    }

    @Test
    func reportListsEveryUsageWindowEachAccountHas() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func usage(_ windows: [(minutes: Int, usedPercent: Int)]) -> UsageSnapshot {
            UsageSnapshot(
                provider: .codex,
                planName: nil,
                windows: windows.map { window in
                    UsageWindow(
                        kind: UsageWindowKind(durationMinutes: window.minutes),
                        usedPercent: window.usedPercent,
                        resetsAt: now.addingTimeInterval(3_600),
                        durationMinutes: window.minutes
                    )
                },
                fetchedAt: now
            )
        }
        let plus = makeAccount(id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!, usage: usage([(300, 12), (10_080, 55)]))
        let pro = makeAccount(id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!, usage: usage([(10_080, 95)]))
        let free = makeAccount(id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!, usage: usage([(43_200, 30)]))
        let unusual = makeAccount(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, usage: usage([(11_520, 60)]))
        let unread = makeAccount(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, usage: nil)

        let report = DiagnosticReportBuilder(
            appMetadata: .fixture,
            systemMetadata: .fixture(now: now)
        ).makeReport(
            state: makeMenuState(activeAccount: plus, inactiveAccounts: [pro, free, unusual, unread]),
            events: []
        )

        #expect(report.accounts.map(\.usageWindows) == [
            [
                DiagnosticUsageWindow(kind: "session", title: "Session", usageCategory: "available"),
                DiagnosticUsageWindow(kind: "weekly", title: "Weekly", usageCategory: "limited")
            ],
            [DiagnosticUsageWindow(kind: "weekly", title: "Weekly", usageCategory: "exhausted")],
            [DiagnosticUsageWindow(kind: "monthly", title: "Monthly", usageCategory: "available")],
            [DiagnosticUsageWindow(kind: "other", title: "8 days", usageCategory: "limited")],
            []
        ])
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
    func tokenLikeAuthLikePathAndStableIDValuesAreNotEncoded() throws {
        let rawValues = [
            "sk-proj-abcdefghijklmnopqrstuvwxyz1234567890",
            #"{"access_token":"secret","refresh_token":"secret"}"#,
            "ssh: Could not resolve hostname private.example.com",
            "/Users/raphh/Library/Application Support/Codex/auth.json",
            "acct_stable_secret"
        ]

        let account = makeAccount(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            email: "secret@example.com",
            stableAccountID: rawValues.last,
            usage: makeUsage()
        )
        let report = DiagnosticReportBuilder(
            appMetadata: .fixture,
            systemMetadata: .fixture()
        ).makeReport(
            state: makeMenuState(activeAccount: account, inactiveAccounts: []),
            events: []
        )
        let json = try encodedJSONString(report)

        for rawValue in rawValues {
            #expect(!json.contains(rawValue))
        }
        #expect(!json.contains("secret@example.com"))
        #expect(!json.contains("private.example.com"))
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
        bundleIdentifier: "com.raphhgg.rusage"
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
    inactiveAccounts: [CodexAccount]
) -> MenuBarMenuState {
    MenuBarMenuState(
        activeAccount: activeAccount,
        inactiveAccounts: inactiveAccounts,
        refreshIntervalMinutes: 5,
        statusBarIndicatorStyle: .punchCard,
        statusBarDisplayMode: .iconOnly,
        isBusy: false,
        statusMessage: ""
    )
}
