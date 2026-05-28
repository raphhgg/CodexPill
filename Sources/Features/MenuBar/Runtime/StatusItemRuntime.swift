import AppKit

struct StatusItemRuntimePresentation {
    let activeAccount: CodexAccount?
    let indicatorStyle: StatusBarIndicatorStyle
    let monochrome: Bool
    let displayMode: StatusBarDisplayMode
    let progressAccentColor: NSColor

    init(
        activeAccount: CodexAccount?,
        indicatorStyle: StatusBarIndicatorStyle,
        monochrome: Bool,
        displayMode: StatusBarDisplayMode,
        progressAccentColor: NSColor = StatusBarProgressColorDefaults.accent
    ) {
        self.activeAccount = activeAccount
        self.indicatorStyle = indicatorStyle
        self.monochrome = monochrome
        self.displayMode = displayMode
        self.progressAccentColor = progressAccentColor
    }
}

struct StatusItemRuntimeSnapshot: Equatable {
    struct Rect: Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    let isHovered: Bool
    let isPointerInsideButton: Bool
    let isTitleVisible: Bool
    let displayedTitle: String?
    let imagePosition: String
    let isHoverPollingActive: Bool
    let buttonFrame: Rect?
    let pointerLocation: Point?
}

@MainActor
final class StatusItemRuntime {
    enum Event: Equatable {
        case hoverEntered
        case hoverExitScheduled
        case hoverExited
        case shortcutRevealStarted
        case shortcutRevealEnded
        case titleBecameVisible(displayedTitle: String?)
        case titleHidden
    }

    var onEvent: ((Event) -> Void)?

    private let statusItem: NSStatusItem
    private let iconRenderer: StatusBarIconRenderer
    private let hoverActivationDelay: TimeInterval
    private let hoverExitDelay: TimeInterval
    private let hoverPollingInterval: TimeInterval

    private var presentation = StatusItemRuntimePresentation(
        activeAccount: nil,
        indicatorStyle: .twinPills,
        monochrome: true,
        displayMode: .iconOnly
    )
    private var hoverActivationTimer: Timer?
    private var hoverExitValidationTimer: Timer?
    private var hoverPollingTimer: Timer?
    private var shortcutRevealTimer: Timer?
    private var hoverTracker: StatusItemHoverTracker?
    private var isMenuOpen = false
    private var isStatusItemHovered = false
    private var isShortcutRevealActive = false
    private var isPointerInsideStatusItem = false
    private var keepsStatusTitleWhileMenuOpen = false
    private var lastRenderedStatusTitleVisible: Bool?

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        iconRenderer: StatusBarIconRenderer = StatusBarIconRenderer(),
        hoverActivationDelay: TimeInterval = 0.18,
        hoverExitDelay: TimeInterval = 0.05,
        hoverPollingInterval: TimeInterval = 0.15
    ) {
        self.statusItem = statusItem
        self.iconRenderer = iconRenderer
        self.hoverActivationDelay = hoverActivationDelay
        self.hoverExitDelay = hoverExitDelay
        self.hoverPollingInterval = hoverPollingInterval
    }

    var menu: NSMenu? {
        get { statusItem.menu }
        set { statusItem.menu = newValue }
    }

    var menuItemCount: Int {
        statusItem.menu?.items.count ?? 0
    }

    var isMenuTrackingOpen: Bool {
        isMenuOpen
    }

    func start(presentation: StatusItemRuntimePresentation) {
        self.presentation = presentation
        configureStatusItemButton()
        syncHoverPolling()
        update(presentation: presentation)
    }

    func invalidate() {
        hoverActivationTimer?.invalidate()
        hoverExitValidationTimer?.invalidate()
        hoverPollingTimer?.invalidate()
        shortcutRevealTimer?.invalidate()
        hoverTracker?.invalidate()
    }

    func update(presentation: StatusItemRuntimePresentation) {
        self.presentation = presentation
        syncHoverPolling()
        updateAppearance()
    }

    func handleMenuWillOpen() {
        isMenuOpen = true
        keepsStatusTitleWhileMenuOpen = isStatusItemHovered
        updateAppearance()
    }

    func handleMenuDidClose() {
        isMenuOpen = false
        keepsStatusTitleWhileMenuOpen = false
        updateAppearance()
    }

    func snapshotState() -> StatusItemRuntimeSnapshot? {
        guard let button = statusItem.button else { return nil }
        let title = button.attributedTitle.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let pointerLocation = NSEvent.mouseLocation
        let buttonFrame = buttonFrame(for: button)
        return StatusItemRuntimeSnapshot(
            isHovered: isStatusItemHovered,
            isPointerInsideButton: buttonFrame.map {
                CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height).contains(pointerLocation)
            } ?? false,
            isTitleVisible: shouldShowStatusTitle && !title.isEmpty,
            displayedTitle: title.isEmpty ? nil : title,
            imagePosition: imagePositionName(button.imagePosition),
            isHoverPollingActive: hoverPollingTimer != nil,
            buttonFrame: buttonFrame,
            pointerLocation: .init(x: pointerLocation.x, y: pointerLocation.y)
        )
    }

    func handleHoverChanged(_ isHovered: Bool) {
        if isHovered {
            handleHoverEnter()
        } else {
            scheduleHoverCancellation()
        }
    }

    func revealTitleTemporarily(duration: TimeInterval = 3) {
        guard !isShortcutRevealActive else {
            endShortcutReveal()
            return
        }

        shortcutRevealTimer?.invalidate()
        isShortcutRevealActive = true
        onEvent?(.shortcutRevealStarted)
        updateAppearance()

        shortcutRevealTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.endShortcutReveal()
            }
        }
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        let primary = presentation.activeAccount?.rateLimits?.sessionWindow?.displayedUsedPercent()
        let secondary = presentation.activeAccount?.rateLimits?.weeklyWindow?.displayedUsedPercent()

        button.image = iconRenderer.makeImage(
            style: presentation.indicatorStyle,
            primaryPercent: primary,
            secondaryPercent: secondary,
            monochrome: presentation.monochrome,
            primaryColor: presentation.progressAccentColor,
            secondaryColor: presentation.progressAccentColor
        )
        button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)

        if shouldShowStatusTitle {
            let title = statusItemHoverTitle(for: presentation.activeAccount)
            button.imagePosition = .imageLeading
            button.title = title
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        }

        button.toolTip = statusItemTooltipText(for: presentation.activeAccount)
        recordStatusTitleVisibilityTransition(
            isVisible: shouldShowStatusTitle,
            displayedTitle: shouldShowStatusTitle ? button.title : nil
        )
    }

    private var shouldShowStatusTitle: Bool {
        StatusItemTitleVisibilityPolicy(
            displayMode: presentation.displayMode,
            isStatusItemHovered: isStatusItemHovered,
            isShortcutRevealActive: isShortcutRevealActive,
            isMenuOpen: isMenuOpen,
            keepsStatusTitleWhileMenuOpen: keepsStatusTitleWhileMenuOpen
        ).shouldShowTitle
    }

    private var shouldPollHoverState: Bool {
        presentation.displayMode == .textOnHover
    }

    private func endShortcutReveal() {
        shortcutRevealTimer?.invalidate()
        shortcutRevealTimer = nil
        guard isShortcutRevealActive else { return }
        isShortcutRevealActive = false
        onEvent?(.shortcutRevealEnded)
        updateAppearance()
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }
        button.target = nil
        button.action = nil
        button.sendAction(on: [])
        button.imageHugsTitle = true

        if hoverTracker == nil {
            let tracker = StatusItemHoverTracker(button: button)
            tracker.onHoverChanged = { [weak self] isHovered in
                self?.handleHoverChanged(isHovered)
            }
            hoverTracker = tracker
        }

        hoverTracker?.installIfNeeded()
    }

    private func startHoverPolling() {
        guard hoverPollingTimer == nil else { return }
        hoverPollingTimer = Timer.scheduledTimer(withTimeInterval: hoverPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncPointerState()
            }
        }
    }

    private func stopHoverPolling() {
        hoverPollingTimer?.invalidate()
        hoverPollingTimer = nil
        isPointerInsideStatusItem = false
        if isStatusItemHovered {
            isStatusItemHovered = false
            updateAppearance()
        }
        hoverActivationTimer?.invalidate()
        hoverActivationTimer = nil
        hoverExitValidationTimer?.invalidate()
        hoverExitValidationTimer = nil
    }

    private func syncHoverPolling() {
        if shouldPollHoverState {
            startHoverPolling()
        } else {
            stopHoverPolling()
        }
    }

    private func syncPointerState() {
        let isPointerInside = isPointerInsideButtonBounds
        guard isPointerInside != isPointerInsideStatusItem else { return }
        isPointerInsideStatusItem = isPointerInside
        handleHoverChanged(isPointerInside)
    }

    private func handleHoverEnter() {
        hoverExitValidationTimer?.invalidate()
        if isMenuOpen {
            guard !isStatusItemHovered else {
                updateAppearance()
                return
            }
            isStatusItemHovered = true
            onEvent?(.hoverEntered)
            updateAppearance()
            return
        }

        hoverActivationTimer?.invalidate()
        if hoverActivationDelay <= 0 {
            activateHoverIfNeeded()
            return
        }

        hoverActivationTimer = Timer.scheduledTimer(withTimeInterval: hoverActivationDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activateHoverIfNeeded()
            }
        }
    }

    private func activateHoverIfNeeded() {
        guard !isMenuOpen else { return }
        guard !isStatusItemHovered else { return }
        isStatusItemHovered = true
        onEvent?(.hoverEntered)
        updateAppearance()
    }

    private func scheduleHoverCancellation() {
        hoverExitValidationTimer?.invalidate()
        onEvent?(.hoverExitScheduled)

        if hoverExitDelay <= 0 {
            cancelHover()
            return
        }

        hoverExitValidationTimer = Timer.scheduledTimer(withTimeInterval: hoverExitDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelHover()
            }
        }
    }

    private func cancelHover() {
        hoverActivationTimer?.invalidate()
        hoverActivationTimer = nil
        hoverExitValidationTimer?.invalidate()
        guard !isPointerInsideButtonBounds else { return }
        guard isStatusItemHovered else { return }
        isStatusItemHovered = false
        onEvent?(.hoverExited)
        updateAppearance()
    }

    private var isPointerInsideButtonBounds: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let pointerLocation = NSEvent.mouseLocation
        let windowLocation = window.convertPoint(fromScreen: pointerLocation)
        let buttonLocation = button.convert(windowLocation, from: nil)
        return !StatusItemHoverExitPolicy.shouldEndHover(
            pointerLocation: buttonLocation,
            in: button.bounds
        )
    }

    private func recordStatusTitleVisibilityTransition(isVisible: Bool, displayedTitle: String?) {
        defer { lastRenderedStatusTitleVisible = isVisible }
        guard let lastRenderedStatusTitleVisible else { return }
        guard lastRenderedStatusTitleVisible != isVisible else { return }

        if isVisible {
            onEvent?(.titleBecameVisible(displayedTitle: displayedTitle))
        } else {
            onEvent?(.titleHidden)
        }
    }

    private func buttonFrame(for button: NSStatusBarButton) -> StatusItemRuntimeSnapshot.Rect? {
        guard let window = button.window else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        let frameInScreen = window.convertToScreen(frameInWindow)
        return .init(
            x: frameInScreen.origin.x,
            y: frameInScreen.origin.y,
            width: frameInScreen.size.width,
            height: frameInScreen.size.height
        )
    }

    private func imagePositionName(_ position: NSControl.ImagePosition) -> String {
        switch position {
        case .imageOnly:
            return "imageOnly"
        case .imageLeading:
            return "imageLeading"
        case .imageTrailing:
            return "imageTrailing"
        case .imageLeft:
            return "imageLeft"
        case .imageRight:
            return "imageRight"
        case .imageBelow:
            return "imageBelow"
        case .imageAbove:
            return "imageAbove"
        case .imageOverlaps:
            return "imageOverlaps"
        case .noImage:
            return "noImage"
        @unknown default:
            return "unknown"
        }
    }
}
