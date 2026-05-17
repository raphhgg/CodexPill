import AppKit
import Foundation
import Testing

@testable import CodexPill

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
                activeAccount: makeAccount(),
                indicatorStyle: .dualArcBadge,
                monochrome: false,
                displayMode: .iconAndText
            )
        )

        let snapshot = try! #require(runtime.snapshotState())

        #expect(snapshot.isTitleVisible)
        #expect(snapshot.displayedTitle == "S 42% W 68%")
        #expect(snapshot.imagePosition == "imageLeading")
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
                activeAccount: makeAccount(),
                indicatorStyle: .dualArcBadge,
                monochrome: false,
                displayMode: .iconOnly
            )
        )

        #expect(try! #require(runtime.snapshotState()).isHoverPollingActive == false)

        runtime.update(
            presentation: .init(
                activeAccount: makeAccount(),
                indicatorStyle: .dualArcBadge,
                monochrome: false,
                displayMode: .iconAndText
            )
        )
        #expect(try! #require(runtime.snapshotState()).isHoverPollingActive == false)

        runtime.update(
            presentation: .init(
                activeAccount: makeAccount(),
                indicatorStyle: .dualArcBadge,
                monochrome: false,
                displayMode: .textOnHover
            )
        )
        #expect(try! #require(runtime.snapshotState()).isHoverPollingActive)

        runtime.update(
            presentation: .init(
                activeAccount: makeAccount(),
                indicatorStyle: .dualArcBadge,
                monochrome: false,
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
                activeAccount: makeAccount(),
                indicatorStyle: .dualArcBadge,
                monochrome: false,
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
                activeAccount: makeAccount(),
                indicatorStyle: .dualArcBadge,
                monochrome: false,
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
                activeAccount: makeAccount(),
                indicatorStyle: .dualArcBadge,
                monochrome: false,
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

    private func makeAccount() -> CodexAccount {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        return CodexAccount(
            id: UUID(),
            name: "Primary",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now,
            updatedAt: now,
            email: "primary@example.com",
            planType: "pro",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "pro",
                primary: .init(
                    usedPercent: 42,
                    resetsAt: nil,
                    windowDurationMinutes: nil
                ),
                secondary: .init(
                    usedPercent: 68,
                    resetsAt: nil,
                    windowDurationMinutes: nil
                ),
                fetchedAt: now
            ),
            identity: .empty
        )
    }
}
