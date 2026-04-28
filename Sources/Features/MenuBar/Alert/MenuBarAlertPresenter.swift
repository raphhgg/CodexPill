import AppKit

@MainActor
protocol AppIconSource {
    func appIconImage() -> NSImage?
}

@MainActor
struct BundleAppIconSource: AppIconSource {
    func appIconImage() -> NSImage? {
        if let resourceIcon = NSImage.codexPillAppIcon() {
            return resourceIcon
        }

        if let applicationIcon = NSApp.applicationIconImage {
            return applicationIcon
        }

        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

extension NSImage {
    static func codexPillAppIcon(bundle: Bundle = .main) -> NSImage? {
        guard let iconURL = bundle.url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: iconURL)
    }
}

@MainActor
protocol MenuBarAlertPresenter {
    func presentTextInput(_ request: MenuBarTextInputAlertRequest) -> String?
    func presentConfirmation(_ request: MenuBarConfirmationAlertRequest) -> Bool
    func presentInfo(_ request: MenuBarInfoAlertRequest)
}

struct MenuBarTextInputAlertRequest {
    let messageText: String
    let informativeText: String
    let fieldTitle: String
    let placeholder: String
    let confirmTitle: String
    let cancelTitle: String
}

struct MenuBarConfirmationAlertRequest {
    let messageText: String
    let informativeText: String
    let confirmTitle: String
    let cancelTitle: String
}

struct MenuBarInfoAlertRequest {
    let messageText: String
    let informativeText: String
    let style: NSAlert.Style
    let buttonTitle: String
}

@MainActor
final class SystemMenuBarAlertPresenter {
    private let environment: [String: String]
    private let appIconSource: AppIconSource

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appIconSource: AppIconSource? = nil
    ) {
        self.environment = environment
        self.appIconSource = appIconSource ?? BundleAppIconSource()
    }

    func presentTextInput(_ request: MenuBarTextInputAlertRequest) -> String? {
        guard !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment) else {
            return nil
        }

        let field = NSTextField(string: "")
        field.placeholderString = request.placeholder

        let alert = NSAlert()
        configure(alert: alert)
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = .informational
        alert.accessoryView = textFieldAccessoryView(
            title: request.fieldTitle,
            field: field,
            statusText: nil,
            statusColor: .secondaryLabelColor
        )
        alert.addButton(withTitle: request.confirmTitle)
        alert.addButton(withTitle: request.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    func presentConfirmation(_ request: MenuBarConfirmationAlertRequest) -> Bool {
        guard !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment) else {
            return false
        }

        let alert = NSAlert()
        configure(alert: alert)
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: request.confirmTitle)
        alert.addButton(withTitle: request.cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentInfo(_ request: MenuBarInfoAlertRequest) {
        guard !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment) else {
            return
        }

        let alert = NSAlert()
        configure(alert: alert)
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = request.style
        alert.addButton(withTitle: request.buttonTitle)
        alert.runModal()
    }

    private func textFieldAccessoryView(
        title: String,
        field: NSTextField,
        statusText: String?,
        statusColor: NSColor
    ) -> NSView {
        configureAlertTextField(field)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(field)

        if let statusText {
            let statusLabel = NSTextField(labelWithString: statusText)
            statusLabel.lineBreakMode = .byWordWrapping
            statusLabel.maximumNumberOfLines = 2
            statusLabel.textColor = statusColor
            statusLabel.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(statusLabel)
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: max(56, stack.fittingSize.height)))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func configure(alert: NSAlert) {
        alert.icon = appIconSource.appIconImage()
    }

    private func configureAlertTextField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 320),
            field.heightAnchor.constraint(equalToConstant: 26)
        ])
    }
}

extension SystemMenuBarAlertPresenter: MenuBarAlertPresenter {}
