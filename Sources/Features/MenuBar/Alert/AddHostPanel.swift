import AppKit
import Combine
import SwiftUI

@MainActor
final class AddHostPanelController: NSObject, NSWindowDelegate {
    private let request: MenuBarHostSetupPanelRequest
    private let panelWindowFactory: PanelWindowFactory
    private let model: AddHostPanelModel
    private let onPresented: () -> Void
    private let onCancelled: () -> Void

    private var completion: CheckedContinuation<RemoteHost?, Never>?
    private var isFinishing = false

    private lazy var panel: NSPanel = {
        let panel = panelWindowFactory.makePanel(
            title: self.request.messageText,
            size: NSSize(width: 520, height: 274)
        )
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: self.makeView())
        return panel
    }()

    init(
        request: MenuBarHostSetupPanelRequest,
        panelWindowFactory: PanelWindowFactory,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>,
        onPresented: @escaping () -> Void,
        onCancelled: @escaping () -> Void,
        onValidationStarted: @escaping (RemoteHost) -> Void,
        onValidationFinished: @escaping (RemoteHost, Result<Void, Error>) -> Void
    ) {
        self.request = request
        self.panelWindowFactory = panelWindowFactory
        self.model = AddHostPanelModel(
            request: request,
            testConnection: testConnection,
            onValidationStarted: onValidationStarted,
            onValidationFinished: onValidationFinished
        )
        self.onPresented = onPresented
        self.onCancelled = onCancelled
        super.init()
    }

    func runModal() async -> RemoteHost? {
        await withCheckedContinuation { continuation in
            completion = continuation
            NSApp.activate(ignoringOtherApps: true)
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            onPresented()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard !isFinishing, completion != nil else { return }
        model.cancelValidation()
        onCancelled()
        finish(with: nil)
    }

    private func makeView() -> AddHostPanel {
        AddHostPanel(
            request: request,
            model: model,
            onCancel: { [weak self] in self?.cancel() },
            onAddHost: { [weak self] in self?.submit() }
        )
    }

    private func cancel() {
        model.cancelValidation()
        onCancelled()
        finish(with: nil)
    }

    private func submit() {
        guard let remoteHost = model.makeRemoteHostForSubmission() else { return }
        model.cancelValidation()
        finish(with: remoteHost)
    }

    private func finish(with response: RemoteHost?) {
        guard let completion, !isFinishing else { return }
        self.completion = nil
        isFinishing = true
        panel.makeFirstResponder(nil)
        panel.endEditing(for: nil)
        panel.close()
        panel.orderOut(nil)
        isFinishing = false
        completion.resume(returning: response)
    }
}

@MainActor
private final class AddHostPanelModel: ObservableObject {
    @Published var hostName = ""
    @Published var destination = "" {
        didSet { updateDestination(destination) }
    }
    @Published private(set) var formState: MenuBarHostSetupFormState

    private let testConnection: (RemoteHost) async -> Result<Void, Error>
    private let onValidationStarted: (RemoteHost) -> Void
    private let onValidationFinished: (RemoteHost, Result<Void, Error>) -> Void
    private let validationDelay: Duration = .milliseconds(600)
    private var validationTask: Task<Void, Never>?
    private var validationGeneration = 0

    init(
        request: MenuBarHostSetupPanelRequest,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>,
        onValidationStarted: @escaping (RemoteHost) -> Void,
        onValidationFinished: @escaping (RemoteHost, Result<Void, Error>) -> Void
    ) {
        self.formState = MenuBarHostSetupFormState(destination: "", idleStatusText: request.idleStatusText)
        self.testConnection = testConnection
        self.onValidationStarted = onValidationStarted
        self.onValidationFinished = onValidationFinished
    }

    var canSubmit: Bool {
        formState.canSubmit
    }

    var statusText: String {
        formState.statusMessage
    }

    var statusKind: MenuBarHostSetupStatusKind {
        formState.statusKind
    }

    var isTesting: Bool {
        formState.isTesting
    }

    func validateImmediatelyOrSubmit(onSubmit: () -> Void) {
        if canSubmit {
            onSubmit()
        } else {
            performValidation(immediately: true)
        }
    }

    func makeRemoteHostForSubmission() -> RemoteHost? {
        formState.updateDestination(destination)
        guard let host = formState.validatedHost, formState.canSubmit else { return nil }
        return RemoteHost(destination: host.destination, displayName: hostName)
    }

    func cancelValidation() {
        validationTask?.cancel()
        validationTask = nil
    }

    private func updateDestination(_ value: String) {
        formState.updateDestination(value)
        performValidation(immediately: false)
    }

    private func performValidation(immediately: Bool) {
        validationTask?.cancel()
        let destination = formState.trimmedDestination
        guard !destination.isEmpty else { return }

        validationGeneration += 1
        let generation = validationGeneration
        let host = RemoteHost(destination: destination)
        validationTask = Task { @MainActor [weak self] in
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
                guard self.formState.trimmedDestination == host.destination else { return }
                self.formState.beginTesting()
                self.onValidationStarted(host)
            }

            let result = await self.testConnection(host).map { host }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == self.validationGeneration else { return }
                guard self.formState.trimmedDestination == host.destination else { return }
                self.formState.finishTesting(with: result)
                self.onValidationFinished(host, result.map { _ in () })
            }
        }
    }
}

private struct AddHostPanel: View {
    private enum Field {
        case destination
    }

    private enum AccessibilityID {
        static let hostNameField = "add-host-host-name-field"
        static let destinationField = "add-host-destination-field"
    }

    let request: MenuBarHostSetupPanelRequest
    @ObservedObject var model: AddHostPanelModel
    let onCancel: () -> Void
    let onAddHost: () -> Void
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.informativeText)
                .font(.system(size: 14))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text(request.nameFieldTitle)
                    .font(.system(size: 13, weight: .semibold))
                TextField(request.namePlaceholder, text: $model.hostName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier(AccessibilityID.hostNameField)
                    .accessibilityLabel(request.nameFieldTitle)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(request.fieldTitle)
                    .font(.system(size: 13, weight: .semibold))
                TextField(request.placeholder, text: $model.destination)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .focused($focusedField, equals: .destination)
                    .accessibilityIdentifier(AccessibilityID.destinationField)
                    .accessibilityLabel(request.fieldTitle)
                    .onSubmit {
                        model.validateImmediatelyOrSubmit(onSubmit: onAddHost)
                    }
            }

            HStack(spacing: 8) {
                if model.isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else if let imageName = statusImageName {
                    Image(systemName: imageName)
                        .foregroundStyle(statusColor)
                }

                Text(model.statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 8) {
                Spacer()
                Button(request.cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(request.confirmTitle, action: onAddHost)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSubmit)
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(width: 520)
        .onAppear {
            focusedField = .destination
            if ProcessInfo.processInfo.environment["CODEXPILL_VALIDATION_SCENARIO"] == "live-add-host-destination-validation-failed" {
                model.destination = "codexpill-validation.invalid"
            }
        }
    }

    private var statusColor: Color {
        switch model.statusKind {
        case .success:
            return .green
        case .failure:
            return .red
        case .idle, .testing:
            return .secondary
        }
    }

    private var statusImageName: String? {
        switch model.statusKind {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        case .idle, .testing:
            return nil
        }
    }
}
