import AppKit

struct MenuBarTextInputAlertRequest {
    let messageText: String
    let informativeText: String
    let fieldTitle: String
    let placeholder: String
    let confirmTitle: String
    let cancelTitle: String
}

struct MenuBarHostSetupAlertRequest {
    let messageText: String
    let informativeText: String
    let fieldTitle: String
    let placeholder: String
    let nameFieldTitle: String
    let namePlaceholder: String
    let confirmTitle: String
    let cancelTitle: String
    let idleStatusText: String
    let successStatusText: String
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
final class MenuBarAlertPresenter {
    func presentTextInput(_ request: MenuBarTextInputAlertRequest) -> String? {
        let field = NSTextField(string: "")
        field.placeholderString = request.placeholder

        let alert = NSAlert()
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
        let alert = NSAlert()
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: request.confirmTitle)
        alert.addButton(withTitle: request.cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentInfo(_ request: MenuBarInfoAlertRequest) {
        let alert = NSAlert()
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = request.style
        alert.addButton(withTitle: request.buttonTitle)
        alert.runModal()
    }

    func presentHostSetup(
        _ request: MenuBarHostSetupAlertRequest,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>,
        onPresented: @escaping () -> Void = {},
        onCancelled: @escaping () -> Void = {},
        onValidationStarted: @escaping (RemoteHost) -> Void = { _ in },
        onValidationFinished: @escaping (RemoteHost, Result<Void, Error>) -> Void = { _, _ in }
    ) async -> RemoteHost? {
        let controller = HostSetupWindowController(
            request: request,
            testConnection: testConnection,
            onPresented: onPresented,
            onCancelled: onCancelled,
            onValidationStarted: onValidationStarted,
            onValidationFinished: onValidationFinished
        )
        return await controller.runModal()
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

    private func configureAlertTextField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 320),
            field.heightAnchor.constraint(equalToConstant: 26)
        ])
    }
}

private final class LiveValidationTextField: NSTextField {
    var onTextDidChange: (() -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextDidChange?()
    }
}

@MainActor
private final class HostSetupWindowController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private let request: MenuBarHostSetupAlertRequest
    private let testConnection: (RemoteHost) async -> Result<Void, Error>
    private let onPresented: () -> Void
    private let onCancelled: () -> Void
    private let onValidationStarted: (RemoteHost) -> Void
    private let onValidationFinished: (RemoteHost, Result<Void, Error>) -> Void
    private let validationDelay: Duration = .milliseconds(600)

    private var state: MenuBarHostSetupFormState
    private var modalResponse: RemoteHost?
    private var validationTask: Task<Void, Never>?
    private var validationGeneration = 0
    private var completion: CheckedContinuation<RemoteHost?, Never>?
    private var isFinishing = false
    private lazy var destinationField: LiveValidationTextField = {
        let field = LiveValidationTextField(string: "")
        field.placeholderString = request.placeholder
        field.delegate = self
        field.onTextDidChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDestinationChanged()
            }
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 300)
        ])
        return field
    }()

    private lazy var nameField: NSTextField = {
        let field = NSTextField(string: "")
        field.placeholderString = request.namePlaceholder
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 300)
        ])
        return field
    }()

    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: request.idleStatusText)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.textColor = .secondaryLabelColor
        return label
    }()

    private lazy var statusIconView: NSImageView = {
        let view = NSImageView()
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        view.contentTintColor = .secondaryLabelColor
        view.isHidden = true
        return view
    }()

    private lazy var progressIndicator: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isDisplayedWhenStopped = false
        return indicator
    }()

    private lazy var cancelButton: NSButton = {
        let button = NSButton(title: request.cancelTitle, target: self, action: #selector(handleCancel))
        button.keyEquivalent = "\u{1b}"
        return button
    }()

    private lazy var addButton: NSButton = {
        let button = NSButton(title: request.confirmTitle, target: self, action: #selector(handleAdd))
        button.keyEquivalent = "\r"
        return button
    }()

    private lazy var window: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 244),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = request.messageText
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.delegate = self
        panel.contentView = contentView()
        panel.initialFirstResponder = destinationField
        return panel
    }()

    init(
        request: MenuBarHostSetupAlertRequest,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>,
        onPresented: @escaping () -> Void,
        onCancelled: @escaping () -> Void,
        onValidationStarted: @escaping (RemoteHost) -> Void,
        onValidationFinished: @escaping (RemoteHost, Result<Void, Error>) -> Void
    ) {
        self.request = request
        self.testConnection = testConnection
        self.onPresented = onPresented
        self.onCancelled = onCancelled
        self.onValidationStarted = onValidationStarted
        self.onValidationFinished = onValidationFinished
        self.state = MenuBarHostSetupFormState(destination: "", idleStatusText: request.idleStatusText)
        super.init()
    }

    func runModal() async -> RemoteHost? {
        syncViewState()
        return await withCheckedContinuation { continuation in
            self.completion = continuation
            NSApp.activate(ignoringOtherApps: true)
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(destinationField)
            onPresented()
        }
    }

    private func handleDestinationChanged() {
        state.updateDestination(currentDestinationInput())
        syncViewState()
        scheduleValidation()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }

        if state.canSubmit {
            handleAdd()
        } else {
            performValidation(immediately: true)
        }
        return true
    }

    private func contentView() -> NSView {
        let messageLabel = NSTextField(labelWithString: request.informativeText)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0

        let fieldTitle = NSTextField(labelWithString: request.fieldTitle)
        fieldTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let nameFieldTitle = NSTextField(labelWithString: request.nameFieldTitle)
        nameFieldTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let statusRow = NSStackView(views: [progressIndicator, statusIconView, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        statusRow.detachesHiddenViews = true

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [spacer, cancelButton, addButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let stack = NSStackView(views: [messageLabel, nameFieldTitle, nameField, fieldTitle, destinationField, statusRow, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 244))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])
        return content
    }

    private func syncViewState() {
        if destinationField.currentEditor() == nil, destinationField.stringValue != state.destination {
            destinationField.stringValue = state.destination
        }

        statusLabel.stringValue = state.statusMessage
        statusLabel.textColor = statusColor(for: state)
        statusIconView.image = statusImage(for: state)
        statusIconView.contentTintColor = statusColor(for: state)
        statusIconView.isHidden = state.statusKind == .idle || state.statusKind == .testing

        if state.isTesting {
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            progressIndicator.isHidden = true
        }

        addButton.isEnabled = state.canSubmit
    }

    private func statusColor(for state: MenuBarHostSetupFormState) -> NSColor {
        switch state.statusKind {
        case .success:
            return .systemGreen
        case .idle, .testing:
            return .secondaryLabelColor
        case .failure:
            return .systemRed
        }
    }

    private func statusImage(for state: MenuBarHostSetupFormState) -> NSImage? {
        switch state.statusKind {
        case .success:
            return NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success")
        case .failure:
            return NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
        case .idle, .testing:
            return nil
        }
    }

    @objc
    private func handleCancel() {
        onCancelled()
        finish(with: nil)
    }

    @objc
    private func handleAdd() {
        state.updateDestination(currentDestinationInput())
        guard let host = state.validatedHost, state.canSubmit else { return }
        finish(with: RemoteHost(destination: host.destination, displayName: currentDisplayNameInput()))
    }

    func windowWillClose(_ notification: Notification) {
        guard !isFinishing, completion != nil else { return }
        onCancelled()
        finish(with: nil)
    }

    private func scheduleValidation() {
        performValidation(immediately: false)
    }

    private func currentDestinationInput() -> String {
        destinationField.currentEditor()?.string ?? destinationField.stringValue
    }

    private func currentDisplayNameInput() -> String {
        nameField.currentEditor()?.string ?? nameField.stringValue
    }

    private func finish(with response: RemoteHost?) {
        guard let completion, !isFinishing else { return }
        self.completion = nil
        modalResponse = response
        validationTask?.cancel()
        isFinishing = true
        window.makeFirstResponder(nil)
        window.endEditing(for: nil)
        window.close()
        window.orderOut(nil)
        isFinishing = false
        completion.resume(returning: response)
    }

    private func performValidation(immediately: Bool) {
        validationTask?.cancel()
        let destination = state.trimmedDestination
        guard !destination.isEmpty else {
            syncViewState()
            return
        }

        validationGeneration += 1
        let generation = validationGeneration
        let host = RemoteHost(destination: destination)
        validationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            if !immediately {
                do {
                    try await Task.sleep(for: self.validationDelay)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard generation == self.validationGeneration else { return }
                guard self.state.trimmedDestination == host.destination else { return }
                self.state.beginTesting()
                self.syncViewState()
                self.onValidationStarted(host)
            }

            let result = await self.testConnection(host).map { host }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == self.validationGeneration else { return }
                guard self.state.trimmedDestination == host.destination else { return }
                self.state.finishTesting(with: result)
                self.syncViewState()
                self.onValidationFinished(host, result.map { _ in () })
            }
        }
    }
}
