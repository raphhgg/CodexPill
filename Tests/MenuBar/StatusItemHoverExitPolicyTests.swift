import CoreGraphics
import Testing

@testable import CodexPill

struct StatusItemHoverExitPolicyTests {
    @Test
    func keepsHoverActiveWhenPointerIsStillInsideExpandedButtonBounds() {
        let shouldEndHover = StatusItemHoverExitPolicy.shouldEndHover(
            pointerLocation: CGPoint(x: 14, y: 8),
            in: CGRect(x: 0, y: 0, width: 54, height: 18)
        )

        #expect(!shouldEndHover)
    }

    @Test
    func endsHoverWhenPointerLeavesExpandedButtonBounds() {
        let shouldEndHover = StatusItemHoverExitPolicy.shouldEndHover(
            pointerLocation: CGPoint(x: 60, y: 8),
            in: CGRect(x: 0, y: 0, width: 54, height: 18)
        )

        #expect(shouldEndHover)
    }
}
