import AppKit

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
final class MenuBarAlertPresenter {
    func presentTextInput(_ request: MenuBarTextInputAlertRequest) -> String? {
        let field = NSTextField(string: "")
        field.placeholderString = request.placeholder

        let alert = NSAlert()
        alert.messageText = request.messageText
        alert.informativeText = request.informativeText
        alert.alertStyle = .informational
        alert.accessoryView = textFieldAccessoryView(title: request.fieldTitle, field: field)
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

    private func textFieldAccessoryView(title: String, field: NSTextField) -> NSView {
        configureAlertTextField(field)

        let stack = labeledField(title: title, field: field)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.layoutSubtreeIfNeeded()
        let fittingHeight = max(50, stack.fittingSize.height)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: fittingHeight))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func labeledField(title: String, field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)

        let stack = NSStackView(views: [label, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func configureAlertTextField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 320),
            field.heightAnchor.constraint(equalToConstant: 26)
        ])
    }
}
