import AppKit
import Foundation
import Testing

@testable import CodexPill

@MainActor
struct StatusItemHoverTrackerTests {
    @Test
    func trackingAreaOwnerExposesExpectedObjectiveCSelectors() {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        let tracker = StatusItemHoverTracker(button: button)

        #expect(tracker.responds(to: NSSelectorFromString("mouseEntered:")))
        #expect(tracker.responds(to: NSSelectorFromString("mouseExited:")))
    }
}
