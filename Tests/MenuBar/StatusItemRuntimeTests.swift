import AppKit
import Foundation
import Testing

@testable import RUsage

@MainActor
struct StatusItemRuntimeTests {
    @Test
    func iconAndTextPresentationProducesVisibleTitleSnapshot() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let runtime = StatusItemRuntime(
            statusItem: statusItem,
            hoverActivationDelay: 0,
            hoverExitDelay: 0,
            hoverPollingInterval: 60
        )
        runtime.start(
            presentation: .init(
                source: primaryAccountSource(),
                indicatorStyle: .moon,
                displayMode: .iconAndText
            )
        )

        let snapshot = try! #require(runtime.snapshotState())

        #expect(snapshot.isTitleVisible)
        #expect(snapshot.displayedTitle == "S 42% W 68%")
        #expect(snapshot.imagePosition == "imageLeading")
    }

    @Test
    func nothingConnectedDrawsTheChosenStyleSoAStyleChangeShowsAtOnce() throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let runtime = StatusItemRuntime(statusItem: statusItem, hoverActivationDelay: 0, hoverExitDelay: 0, hoverPollingInterval: 60)
        func pixels() throws -> Data { try #require(statusItem.button?.image?.tiffRepresentation) }

        runtime.start(presentation: .init(source: .nothingConnected, indicatorStyle: .glasses, displayMode: .iconOnly))
        let glasses = try pixels()
        runtime.update(presentation: .init(source: .nothingConnected, indicatorStyle: .moon, displayMode: .iconOnly))
        let moon = try pixels()
        runtime.update(presentation: .init(source: .nothingConnected, indicatorStyle: .punchCard, displayMode: .iconOnly))
        let punchCard = try pixels()

        #expect(Set([glasses, moon, punchCard]).count == 3)
        #expect(punchCard == StatusBarIconRenderer().makeImage(style: .punchCard, reading: .noData).tiffRepresentation)
    }

    @Test
    func hoverPollingRunsOnlyForTextOnHoverMode() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let runtime = StatusItemRuntime(
            statusItem: statusItem,
            hoverActivationDelay: 0,
            hoverExitDelay: 0,
            hoverPollingInterval: 60
        )
        runtime.start(
            presentation: .init(
                source: primaryAccountSource(),
                indicatorStyle: .moon,
                displayMode: .iconOnly
            )
        )

        #expect(try! #require(runtime.snapshotState()).isHoverPollingActive == false)

        runtime.update(
            presentation: .init(
                source: primaryAccountSource(),
                indicatorStyle: .moon,
                displayMode: .iconAndText
            )
        )
        #expect(try! #require(runtime.snapshotState()).isHoverPollingActive == false)

        runtime.update(
            presentation: .init(
                source: primaryAccountSource(),
                indicatorStyle: .moon,
                displayMode: .textOnHover
            )
        )
        #expect(try! #require(runtime.snapshotState()).isHoverPollingActive)

        runtime.update(
            presentation: .init(
                source: primaryAccountSource(),
                indicatorStyle: .moon,
                displayMode: .iconOnly
            )
        )
        #expect(try! #require(runtime.snapshotState()).isHoverPollingActive == false)
    }

    @Test
    func textOnHoverEmitsLifecycleEventsFromRuntimeBoundary() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let runtime = StatusItemRuntime(
            statusItem: statusItem,
            hoverActivationDelay: 0,
            hoverExitDelay: 0,
            hoverPollingInterval: 60
        )
        var events: [StatusItemRuntime.Event] = []
        runtime.onEvent = { events.append($0) }
        runtime.start(
            presentation: .init(
                source: primaryAccountSource(),
                indicatorStyle: .moon,
                displayMode: .textOnHover
            )
        )

        runtime.handleHoverChanged(true)
        runtime.handleHoverChanged(false)

        #expect(events.contains(.hoverEntered))
        #expect(events.contains(.hoverExitScheduled))
        #expect(events.contains(.hoverExited))
        #expect(events.contains(.titleBecameVisible(displayedTitle: "S 42% W 68%")))
        #expect(events.contains(.titleHidden))
    }

    @Test
    func shortcutRevealShowsIconOnlyTitleWithoutChangingDisplayMode() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let runtime = StatusItemRuntime(
            statusItem: statusItem,
            hoverActivationDelay: 0,
            hoverExitDelay: 0,
            hoverPollingInterval: 60
        )
        runtime.start(
            presentation: .init(
                source: primaryAccountSource(),
                indicatorStyle: .moon,
                displayMode: .iconOnly
            )
        )

        #expect(try! #require(runtime.snapshotState()).isTitleVisible == false)

        runtime.revealTitleTemporarily(duration: 60)

        let snapshot = try! #require(runtime.snapshotState())
        #expect(snapshot.isTitleVisible)
        #expect(snapshot.displayedTitle == "S 42% W 68%")
    }

    @Test
    func repeatedShortcutRevealCollapsesVisibleTitle() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let runtime = StatusItemRuntime(
            statusItem: statusItem,
            hoverActivationDelay: 0,
            hoverExitDelay: 0,
            hoverPollingInterval: 60
        )
        var events: [StatusItemRuntime.Event] = []
        runtime.onEvent = { events.append($0) }
        runtime.start(
            presentation: .init(
                source: primaryAccountSource(),
                indicatorStyle: .moon,
                displayMode: .iconOnly
            )
        )

        runtime.revealTitleTemporarily(duration: 60)
        runtime.revealTitleTemporarily(duration: 60)

        let snapshot = try! #require(runtime.snapshotState())
        #expect(!snapshot.isTitleVisible)
        #expect(events.contains(.shortcutRevealStarted))
        #expect(events.contains(.shortcutRevealEnded))
    }

    private func primaryAccountSource() -> StatusItemSource {
        MenuBarMenuState(activeAccount: makeAccount(name: "Primary", usage: makeUsage()), inactiveAccounts: []).statusItemSource
    }
}
