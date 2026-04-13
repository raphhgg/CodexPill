import AppKit

final class StatusItemHoverView: NSView {
    private weak var button: NSStatusBarButton?
    var onHoverChanged: ((Bool) -> Void)?
    var onMouseDown: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    init(button: NSStatusBarButton) {
        self.button = button
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        button?.mouseDown(with: event)
    }
}
