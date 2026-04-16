import Foundation
import Testing

@testable import CodexPill

struct MenuBarLiveValidationTests {
    @Test
    func fileSinkWritesSnapshotJSON() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("live-menu-snapshot.json")
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

        try FileMenuBarValidationSink(outputURL: outputURL).record(snapshot)

        let data = try Data(contentsOf: outputURL)
        let decoded = try JSONDecoder().decode(MenuBarValidationSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test
    func configurationReturnsSinkOnlyWhenOutputPathIsPresent() {
        #expect(MenuBarValidationConfiguration.makeSink(environment: [:]) == nil)
        #expect(
            MenuBarValidationConfiguration.makeSink(
                environment: [MenuBarValidationConfiguration.outputPathEnvironmentKey: "/tmp/codexpill-live-menu.json"]
            ) is FileMenuBarValidationSink
        )
    }
}
