import Foundation
import Testing

@testable import CodexPill

struct MenuBarLiveValidationTests {
    @Test
    func fileSinkWritesSnapshotJSON() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("live-menu-snapshot.json")
        let eventsOutputURL = temporaryDirectory.appendingPathComponent("validation-events.jsonl")
        let snapshot = MenuBarValidationSnapshot(
            sections: [
                .init(title: "Current Account", items: ["Primary • Pro • primary@example.com"])
            ],
            statusMessage: "Refreshing account data...",
            currentAccount: .init(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                identityDigest: "digest-primary"
            ),
            hasStatusItemContentData: true,
            effectiveStatusBarDisplayMode: "iconAndText",
            statusItem: nil,
            actionTrace: nil,
            menuItems: [
                .init(
                    title: "Status Item",
                    isEnabled: true,
                    state: "off",
                    hasAction: false,
                    actionSelector: nil,
                    isSeparator: false,
                    children: []
                )
            ]
        )

        try FileMenuBarValidationSink(outputURL: outputURL, eventsOutputURL: eventsOutputURL).record(snapshot)

        let data = try Data(contentsOf: outputURL)
        let decoded = try JSONDecoder().decode(MenuBarValidationSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test
    func fileSinkAppendsValidationEventsJSONL() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("live-menu-snapshot.json")
        let eventsOutputURL = temporaryDirectory.appendingPathComponent("validation-events.jsonl")
        let sink = FileMenuBarValidationSink(outputURL: outputURL, eventsOutputURL: eventsOutputURL)
        let firstEvent = MenuBarValidationEvent(
            timestamp: Date(timeIntervalSince1970: 1_744_200_000),
            scenario: "live-status-item-hover",
            proofLayer: "live_ui",
            invariantIds: ["menubar.text_on_hover.stays_visible_inside_resized_bounds"],
            event: "status_item_hover_entered",
            step: "hover_enter",
            payload: ["displayedTitle": "S 42% W 68%"]
        )
        let secondEvent = MenuBarValidationEvent(
            timestamp: Date(timeIntervalSince1970: 1_744_200_001),
            scenario: "live-status-item-hover",
            proofLayer: "live_ui",
            invariantIds: ["menubar.text_on_hover.stays_visible_inside_resized_bounds"],
            event: "status_item_title_hidden",
            step: "hover_title_hidden"
        )

        try sink.record(firstEvent)
        try sink.record(secondEvent)

        let lines = try String(contentsOf: eventsOutputURL)
            .split(separator: "\n")
            .map(String.init)
        let decoded = try lines.map { line in
            try JSONDecoder().decode(MenuBarValidationEvent.self, from: Data(line.utf8))
        }

        #expect(decoded == [firstEvent, secondEvent])
    }

    @Test
    func configurationReturnsSinkOnlyWhenOutputPathIsPresent() {
        #expect(MenuBarValidationConfiguration.makeSink(environment: [:]) == nil)
        #expect(
            MenuBarValidationConfiguration.makeSink(
                environment: [
                    MenuBarValidationConfiguration.outputPathEnvironmentKey: "/tmp/codexpill-live-menu.json",
                    MenuBarValidationConfiguration.eventsOutputPathEnvironmentKey: "/tmp/validation-events.jsonl"
                ]
            ) is FileMenuBarValidationSink
        )
        #expect(MenuBarValidationConfiguration.scenario(environment: [:]) == nil)
        #expect(
            MenuBarValidationConfiguration.scenario(
                environment: [MenuBarValidationConfiguration.scenarioEnvironmentKey: "live-status-item-hover"]
            ) == "live-status-item-hover"
        )
    }
}
