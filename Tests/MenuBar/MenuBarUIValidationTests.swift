import AppKit
import Foundation
import SwiftUI
import Testing

@testable import CodexPill

@MainActor
struct MenuBarUIValidationTests {
    @Test
    func currentAccountSummaryShowsDetailedLimitLines() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeHostedValidationState(for: "hosted-menu-default", now: now),
            now: now
        )

        let summary = try! #require(snapshot.sections.first(where: { $0.title == "Current Account" })?.items.first(where: { $0.contains("Primary • Pro") }))
        #expect(summary.contains("Primary • Pro"))
        #expect(summary.contains("primary@example.com"))
        #expect(summary.contains("Session: 42% used"))
    }

    @Test
    func otherAccountsStayCompact() {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let snapshot = MenuBarValidationSupport.makeSnapshot(
            state: makeHostedValidationState(for: "hosted-menu-default", now: now),
            now: now
        )
        let summary = try! #require(snapshot.sections.first(where: { $0.title == "Other Accounts" })?.items.first)
        #expect(summary.contains("Research • Pro • Session 8% • Weekly 35%"))
        #expect(!summary.contains("research@example.com"))
    }

    @Test
    func hostedMenuScenarioProducesArtifacts() throws {
        let request = try loadValidationRequest() ?? ValidationRequest(
            artifactDirectory: "",
            scenario: "hosted-menu-default"
        )
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = makeHostedValidationState(for: request.scenario, now: now)
        let snapshot = MenuBarValidationSupport.makeSnapshot(state: state, now: now)

        try assertScenarioSnapshot(snapshot, scenario: request.scenario)

        guard !request.artifactDirectory.isEmpty else {
            return
        }

        let artifactDirectory = URL(fileURLWithPath: request.artifactDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        let screenshotURL = artifactDirectory
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent("\(request.scenario).png")
        try FileManager.default.createDirectory(at: screenshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let uiTreeURL = artifactDirectory.appendingPathComponent("ui-tree.json")
        let summaryURL = artifactDirectory.appendingPathComponent("scenario-summary.json")

        try renderHostedValidationView(
            MenuBarValidationSupport.makeHostedValidationView(state: state, now: now),
            to: screenshotURL
        )
        try writeJSON(snapshot, to: uiTreeURL)
        try writeJSON(
            ScenarioSummary(
                scenario: request.scenario,
                assertions: scenarioAssertions(for: request.scenario),
                screenshot: screenshotURL.lastPathComponent,
                uiTree: uiTreeURL.lastPathComponent
            ),
            to: summaryURL
        )
    }

    private func renderHostedValidationView<V: View>(_ view: V, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize
        let frame = NSRect(origin: .zero, size: NSSize(width: max(360, size.width), height: max(1, size.height)))
        hostingView.frame = frame
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: frame) else {
            throw ValidationError.failedToCreateBitmap
        }

        hostingView.cacheDisplay(in: frame, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw ValidationError.failedToEncodePNG
        }

        try pngData.write(to: url, options: .atomic)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func assertScenarioSnapshot(_ snapshot: MenuBarValidationSnapshot, scenario: String) throws {
        switch scenario {
        case "hosted-menu-default":
            #expect(snapshot.sections.map(\.title) == [
                "Current Account",
                "Other Accounts",
                "More Accounts",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.statusMessage == nil)
            #expect(snapshot.sections[1].items.count == 2)
            #expect(snapshot.sections[2].items.count == 1)
            #expect(snapshot.sections[3].items.contains("Save Current Account (disabled)"))

        case "hosted-menu-busy":
            #expect(snapshot.sections.map(\.title) == [
                "Current Account",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.statusMessage == "Refreshing account data...")
            #expect(snapshot.sections[1].items.contains("Save Current Account (disabled)"))
            #expect(snapshot.sections[1].items.contains("Sign In Another Account… (disabled)"))
            #expect(snapshot.sections[1].items.contains("Rename Account"))
            #expect(snapshot.sections[1].items.contains("Remove Account"))

        case "hosted-menu-empty":
            #expect(snapshot.sections.map(\.title) == [
                "Current Account",
                "Manage Accounts",
                "Preferences"
            ])
            #expect(snapshot.sections[0].items == ["No active saved account"])
            #expect(snapshot.sections[1].items.contains("Save Current Account"))
            #expect(snapshot.sections[1].items.contains("Rename Account"))
            #expect(snapshot.sections[1].items.contains("Remove Account"))
            #expect(snapshot.statusMessage == nil)

        default:
            throw ValidationError.unknownScenario(scenario)
        }
    }

    private func scenarioAssertions(for scenario: String) -> [String] {
        switch scenario {
        case "hosted-menu-default":
            return [
                "Current Account section includes the active account summary",
                "Two inactive accounts are visible and one account overflows into More Accounts",
                "Status message is omitted when the menu is not busy"
            ]
        case "hosted-menu-busy":
            return [
                "Busy state exposes only the current account plus shared account and preference controls",
                "Busy status message is rendered into the artifact snapshot",
                "Save and sign-in actions are marked disabled in the snapshot"
            ]
        case "hosted-menu-empty":
            return [
                "Empty state shows no active saved account",
                "Save Current Account remains available when the menu is idle and empty",
                "Remove Account still renders as a stable control even when no saved accounts exist"
            ]
        default:
            return []
        }
    }

    private func loadValidationRequest() throws -> ValidationRequest? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let requestURL = repoRoot
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("verification", isDirectory: true)
            .appendingPathComponent("request.json")

        guard FileManager.default.fileExists(atPath: requestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: requestURL)
        let request = try JSONDecoder().decode(ValidationRequest.self, from: data)
        return request
    }

    private func makeHostedValidationState(for scenario: String, now: Date) -> MenuBarMenuState {
        switch scenario {
        case "hosted-menu-default":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)
            ]

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        case "hosted-menu-busy":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 57,
                weeklyUsedPercent: 73,
                now: now
            )

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: true,
                statusBarIndicatorStyle: .twinPills,
                statusBarDisplayMode: .textOnHover,
                isBusy: true,
                statusMessage: "Refreshing account data..."
            )

        case "hosted-menu-empty":
            return MenuBarMenuState(
                activeAccount: nil,
                inactiveAccounts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 10,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .stackedBars,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        default:
            return makeHostedValidationState(for: "hosted-menu-default", now: now)
        }
    }

    private func makeAccount(
        name: String,
        email: String,
        planType: String,
        sessionUsedPercent: Int,
        weeklyUsedPercent: Int,
        now: Date
    ) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now.addingTimeInterval(-3_600),
            updatedAt: now.addingTimeInterval(-600),
            email: email,
            planType: planType,
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: planType,
                primary: CodexRateLimitWindow(
                    usedPercent: sessionUsedPercent,
                    resetsAt: now.addingTimeInterval(3_600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: weeklyUsedPercent,
                    resetsAt: now.addingTimeInterval(86_400),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now.addingTimeInterval(-300)
            ),
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}

private struct ScenarioSummary: Codable {
    let scenario: String
    let assertions: [String]
    let screenshot: String
    let uiTree: String
}

private struct ValidationRequest: Codable {
    let artifactDirectory: String
    let scenario: String
}

private enum ValidationError: Error {
    case failedToCreateBitmap
    case failedToEncodePNG
    case unknownScenario(String)
}
