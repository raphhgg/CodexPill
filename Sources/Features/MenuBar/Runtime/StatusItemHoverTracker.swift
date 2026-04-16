import AppKit

@MainActor
final class StatusItemHoverTracker: NSObject {
    private weak var button: NSStatusBarButton?
    private var trackingArea: NSTrackingArea?
    var onHoverChanged: ((Bool) -> Void)?

    init(button: NSStatusBarButton) {
        self.button = button
        super.init()
    }

    func installIfNeeded() {
        guard let button else { return }
        let area = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        if let trackingArea {
            button.removeTrackingArea(trackingArea)
        }
        button.addTrackingArea(area)
        trackingArea = area
    }

    func invalidate() {
        guard let button, let trackingArea else { return }
        button.removeTrackingArea(trackingArea)
        self.trackingArea = nil
    }

    @objc(mouseEntered:)
    func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    @objc(mouseExited:)
    func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}
