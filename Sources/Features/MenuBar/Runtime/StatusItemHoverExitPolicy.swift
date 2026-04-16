import CoreGraphics

struct StatusItemHoverExitPolicy {
    static func shouldEndHover(pointerLocation: CGPoint, in buttonBounds: CGRect) -> Bool {
        !buttonBounds.contains(pointerLocation)
    }
}
