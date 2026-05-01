import AppKit
import SwiftUI

enum ShortcutCapturePanelResult: Equatable {
    case cancelled
    case cleared
    case saved(KeyboardShortcut)
}

struct ShortcutCaptureState: Equatable {
    private(set) var capturedShortcut: KeyboardShortcut?
    private(set) var statusText: String
    private(set) var statusKind: StatusKind

    enum StatusKind: Equatable {
        case idle
        case invalid
        case valid
    }

    init(currentShortcut: KeyboardShortcut?) {
        self.capturedShortcut = currentShortcut
        self.statusText = currentShortcut == nil
            ? "Press a shortcut with at least one modifier key."
            : "Press a new shortcut, then save."
        self.statusKind = currentShortcut == nil ? .idle : .valid
    }

    var displayTitle: String {
        capturedShortcut?.displayTitle ?? "Waiting for shortcut"
    }

    var canSave: Bool {
        capturedShortcut?.isValid == true
    }

    mutating func capture(_ shortcut: KeyboardShortcut?) {
        guard let shortcut, shortcut.isValid else {
            capturedShortcut = nil
            statusText = "Shortcuts need at least one modifier key."
            statusKind = .invalid
            return
        }

        capturedShortcut = shortcut
        statusText = "Shortcut ready to save."
        statusKind = .valid
    }

    func saveResult() -> ShortcutCapturePanelResult? {
        guard let capturedShortcut, capturedShortcut.isValid else { return nil }
        return .saved(capturedShortcut)
    }
}

@MainActor
protocol ShortcutCapturePanelPresenter {
    func presentShortcutCapture(currentShortcut: KeyboardShortcut?) -> ShortcutCapturePanelResult
}

@MainActor
final class SystemShortcutCapturePanelPresenter: ShortcutCapturePanelPresenter {
    private let environment: [String: String]
    private let panelWindowFactory: PanelWindowFactory

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appIconSource: AppIconSource? = nil
    ) {
        self.environment = environment
        self.panelWindowFactory = PanelWindowFactory(appIconSource: appIconSource ?? BundleAppIconSource())
    }

    func presentShortcutCapture(currentShortcut: KeyboardShortcut?) -> ShortcutCapturePanelResult {
        guard !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment) else {
            return .cancelled
        }

        let controller = ShortcutCapturePanelController(
            currentShortcut: currentShortcut,
            panelWindowFactory: panelWindowFactory
        )
        return controller.runModal()
    }
}

@MainActor
private final class ShortcutCapturePanelController: NSObject, NSWindowDelegate {
    private let model: ShortcutCapturePanelModel
    private let panelWindowFactory: PanelWindowFactory

    private var result: ShortcutCapturePanelResult = .cancelled
    private var isFinishing = false
    private var monitor: Any?

    private lazy var panel: NSPanel = {
        let panel = panelWindowFactory.makePanel(
            title: "Menu Bar Label Shortcut",
            size: NSSize(width: 500, height: 236)
        )
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: self.makeView())
        return panel
    }()

    init(currentShortcut: KeyboardShortcut?, panelWindowFactory: PanelWindowFactory) {
        self.model = ShortcutCapturePanelModel(currentShortcut: currentShortcut)
        self.panelWindowFactory = panelWindowFactory
        super.init()
    }

    func runModal() -> ShortcutCapturePanelResult {
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        startMonitoringKeyEvents()
        NSApp.runModal(for: panel)
        stopMonitoringKeyEvents()
        return result
    }

    func windowWillClose(_ notification: Notification) {
        guard !isFinishing else { return }
        finish(with: .cancelled)
    }

    private func makeView() -> ShortcutCapturePanel {
        ShortcutCapturePanel(
            model: model,
            onCancel: { [weak self] in self?.finish(with: .cancelled) },
            onClear: { [weak self] in self?.finish(with: .cleared) },
            onSave: { [weak self] in self?.save() }
        )
    }

    private func startMonitoringKeyEvents() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.model.capture(event: event)
            return nil
        }
    }

    private func stopMonitoringKeyEvents() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func save() {
        guard let result = model.saveResult() else {
            model.capture(shortcut: nil)
            return
        }
        finish(with: result)
    }

    private func finish(with result: ShortcutCapturePanelResult) {
        guard !isFinishing else { return }
        isFinishing = true
        self.result = result
        panel.makeFirstResponder(nil)
        panel.endEditing(for: nil)
        panel.close()
        panel.orderOut(nil)
        NSApp.stopModal()
    }
}

@MainActor
final class ShortcutCapturePanelModel: ObservableObject {
    @Published private(set) var state: ShortcutCaptureState

    init(currentShortcut: KeyboardShortcut?) {
        self.state = ShortcutCaptureState(currentShortcut: currentShortcut)
    }

    var displayTitle: String {
        state.displayTitle
    }

    var statusText: String {
        state.statusText
    }

    var canSave: Bool {
        state.canSave
    }

    var statusKind: ShortcutCaptureState.StatusKind {
        state.statusKind
    }

    func capture(event: NSEvent) {
        state.capture(KeyboardShortcut(event: event))
    }

    func capture(shortcut: KeyboardShortcut?) {
        state.capture(shortcut)
    }

    func saveResult() -> ShortcutCapturePanelResult? {
        state.saveResult()
    }
}

private struct ShortcutCapturePanel: View {
    @ObservedObject var model: ShortcutCapturePanelModel
    let onCancel: () -> Void
    let onClear: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Press a shortcut to reveal CodexPill limits from anywhere.")
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            PanelValueBox(
                value: model.displayTitle,
                font: .system(size: 22, weight: .semibold, design: .monospaced),
                textColor: valueColor,
                allowsTextSelection: false
            )

            HStack(spacing: 8) {
                if let statusImageName {
                    Image(systemName: statusImageName)
                        .foregroundStyle(statusColor)
                }
                Text(model.statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Clear", action: onClear)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(width: 500)
    }

    private var valueColor: Color {
        model.canSave ? .primary : .secondary
    }

    private var statusColor: Color {
        switch model.statusKind {
        case .idle:
            return .secondary
        case .invalid:
            return .red
        case .valid:
            return .green
        }
    }

    private var statusImageName: String? {
        switch model.statusKind {
        case .idle:
            return nil
        case .invalid:
            return "exclamationmark.triangle.fill"
        case .valid:
            return "checkmark.circle.fill"
        }
    }
}
