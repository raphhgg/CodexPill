import AppKit

@MainActor
final class SystemAlertPresenter {
    private let suppressesInteractivePrompts: Bool
    private let appIconSource: AppIconSource

    init(
        suppressesInteractivePrompts: Bool,
        appIconSource: AppIconSource? = nil
    ) {
        self.suppressesInteractivePrompts = suppressesInteractivePrompts
        self.appIconSource = appIconSource ?? BundleAppIconSource()
    }

    func presentTextInput(_ request: MenuBarTextInputAlertRequest) -> String? {
        guard !suppressesInteractivePrompts else {
            return nil
        }

        let field = NSTextField(string: "")
        field.placeholderString = request.placeholder
        let validator = TextInputAlertValidator(field: field, requiresNonEmptyValue: request.requiresNonEmptyValue)

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
        validator.confirmButton = alert.buttons.first
        validator.apply()

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    func presentConfirmation(_ request: MenuBarConfirmationAlertRequest) -> Bool {
        guard !suppressesInteractivePrompts else {
            return false
        }

        let alert = NSAlert()
        configure(alert: alert)
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = .informational
        let disclosure = request.detail.map { AlertDisclosureView(title: "Show Change", detail: $0, alert: alert) }
        alert.accessoryView = disclosure
        alert.addButton(withTitle: request.confirmTitle)
        alert.addButton(withTitle: request.cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentInfo(_ request: MenuBarInfoAlertRequest) {
        guard !suppressesInteractivePrompts else {
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

        let horizontalInset: CGFloat = 4
        let fieldWidth: CGFloat = 340
        let container = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: fieldWidth + horizontalInset * 2,
                height: max(56, stack.fittingSize.height)
            )
        )
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
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
            field.widthAnchor.constraint(equalToConstant: 340),
            field.heightAnchor.constraint(equalToConstant: 26)
        ])
    }
}

extension SystemAlertPresenter: AlertPresenter {}

/// A collapsed disclosure row that reveals detail text inside an `NSAlert`.
@MainActor
private final class AlertDisclosureView: NSView {
    private let triangle = NSButton()
    private let detailField: NSTextField
    private let stack = NSStackView()
    private weak var alert: NSAlert?

    init(title: String, detail: String, alert: NSAlert) {
        detailField = NSTextField(wrappingLabelWithString: detail)
        self.alert = alert
        super.init(frame: .zero)

        triangle.bezelStyle = .disclosure
        triangle.setButtonType(.pushOnPushOff)
        triangle.title = ""
        triangle.state = .off
        triangle.target = self
        triangle.action = #selector(toggle)

        let label = NSButton(title: title, target: self, action: #selector(toggleFromLabel))
        label.isBordered = false
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let row = NSStackView(views: [triangle, label])
        row.orientation = .horizontal
        row.spacing = 2

        detailField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        detailField.isSelectable = true
        detailField.preferredMaxLayoutWidth = Self.width
        detailField.isHidden = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(detailField)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            detailField.widthAnchor.constraint(lessThanOrEqualToConstant: Self.width)
        ])
        resizeToFit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let width: CGFloat = 300

    @objc private func toggleFromLabel() {
        triangle.state = triangle.state == .on ? .off : .on
        toggle()
    }

    @objc private func toggle() {
        detailField.isHidden = triangle.state == .off
        resizeToFit()
        alert?.layout()
    }

    private func resizeToFit() {
        setFrameSize(NSSize(width: Self.width, height: stack.fittingSize.height))
    }
}

@MainActor
private final class TextInputAlertValidator: NSObject, NSTextFieldDelegate {
    private let field: NSTextField
    private let requiresNonEmptyValue: Bool
    weak var confirmButton: NSButton?

    init(field: NSTextField, requiresNonEmptyValue: Bool) {
        self.field = field
        self.requiresNonEmptyValue = requiresNonEmptyValue
        super.init()
        field.delegate = self
    }

    func controlTextDidChange(_ notification: Notification) {
        apply()
    }

    func apply() {
        guard requiresNonEmptyValue else {
            confirmButton?.isEnabled = true
            return
        }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        confirmButton?.isEnabled = !value.isEmpty
    }
}
