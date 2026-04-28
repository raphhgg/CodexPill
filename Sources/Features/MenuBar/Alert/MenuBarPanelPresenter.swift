import AppKit
import Combine
import SwiftUI

@MainActor
protocol MenuBarPanelPresenter {
    func presentHostSetup(
        _ request: MenuBarHostSetupPanelRequest,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>,
        onPresented: @escaping () -> Void,
        onCancelled: @escaping () -> Void,
        onValidationStarted: @escaping (RemoteHost) -> Void,
        onValidationFinished: @escaping (RemoteHost, Result<Void, Error>) -> Void
    ) async -> RemoteHost?
    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion: @escaping () async -> Result<CodexAccount, Error>,
        onCancel: @escaping () -> Void
    ) async -> MenuBarAddAccountSignInPanelResult
}

struct MenuBarHostSetupPanelRequest {
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

struct MenuBarAddAccountSignInPanelRequest {
    let messageText: String
    let informativeText: String
    let userCode: String
    let promptURL: URL
    let waitingStatusText: String
    let copiedStatusText: String
    let browserOpenedStatusText: String
    let copyTitle: String
    let openBrowserTitle: String
    let cancelTitle: String
}

enum MenuBarAddAccountSignInPanelResult {
    case completed(CodexAccount)
    case cancelled
    case failed(Error)
}

@MainActor
final class SystemMenuBarPanelPresenter {
    private let environment: [String: String]
    private let appIconSource: AppIconSource

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appIconSource: AppIconSource? = nil
    ) {
        self.environment = environment
        self.appIconSource = appIconSource ?? BundleAppIconSource()
    }
}

extension SystemMenuBarPanelPresenter: MenuBarPanelPresenter {
    func presentHostSetup(
        _ request: MenuBarHostSetupPanelRequest,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>,
        onPresented: @escaping () -> Void = {},
        onCancelled: @escaping () -> Void = {},
        onValidationStarted: @escaping (RemoteHost) -> Void = { _ in },
        onValidationFinished: @escaping (RemoteHost, Result<Void, Error>) -> Void = { _, _ in }
    ) async -> RemoteHost? {
        guard !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment) else {
            onCancelled()
            return nil
        }

        let controller = MenuBarHostSetupPanelController(
            request: request,
            appIconSource: appIconSource,
            testConnection: testConnection,
            onPresented: onPresented,
            onCancelled: onCancelled,
            onValidationStarted: onValidationStarted,
            onValidationFinished: onValidationFinished
        )
        let result = await controller.runModal()
        // Give AppKit one pass to remove the setup panel before a follow-up
        // confirmation panel is presented.
        await Task.yield()
        return result
    }

    func presentAddAccountSignIn(
        _ request: MenuBarAddAccountSignInPanelRequest,
        waitForCompletion: @escaping () async -> Result<CodexAccount, Error>,
        onCancel: @escaping () -> Void
    ) async -> MenuBarAddAccountSignInPanelResult {
        guard !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment) else {
            onCancel()
            return .cancelled
        }

        let controller = MenuBarAddAccountSignInPanelController(
            request: request,
            appIconSource: appIconSource,
            waitForCompletion: waitForCompletion,
            onCancel: onCancel
        )
        return await controller.runModal()
    }
}

@MainActor
private final class MenuBarAddAccountSignInPanelController: NSObject, NSWindowDelegate {
    private let request: MenuBarAddAccountSignInPanelRequest
    private let appIconSource: AppIconSource
    private let waitForCompletion: () async -> Result<CodexAccount, Error>
    private let onCancel: () -> Void

    private var completion: CheckedContinuation<MenuBarAddAccountSignInPanelResult, Never>?
    private var waitTask: Task<Void, Never>?
    private var isFinishing = false
    private var statusText: String

    private lazy var panel: NSPanel = {
        let panel = makePanel(title: self.request.messageText, size: NSSize(width: 500, height: 244), appIconSource: self.appIconSource)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: self.makeView())
        return panel
    }()

    init(
        request: MenuBarAddAccountSignInPanelRequest,
        appIconSource: AppIconSource,
        waitForCompletion: @escaping () async -> Result<CodexAccount, Error>,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.appIconSource = appIconSource
        self.waitForCompletion = waitForCompletion
        self.onCancel = onCancel
        self.statusText = request.waitingStatusText
        super.init()
    }

    func runModal() async -> MenuBarAddAccountSignInPanelResult {
        await withCheckedContinuation { continuation in
            completion = continuation
            NSApp.activate(ignoringOtherApps: true)
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            startWaiting()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard !isFinishing, completion != nil else { return }
        onCancel()
        finish(with: .cancelled)
    }

    private func makeView() -> MenuBarAddAccountSignInPanelView {
        let fallbackStatusText = request.waitingStatusText
        return MenuBarAddAccountSignInPanelView(
            request: request,
            statusText: Binding(
                get: { [weak self] in self?.statusText ?? fallbackStatusText },
                set: { [weak self] in self?.statusText = $0 }
            ),
            onCopy: { [weak self] in self?.copyCode() },
            onOpenBrowser: { [weak self] in self?.openBrowser() },
            onCancel: { [weak self] in self?.cancel() }
        )
    }

    private func startWaiting() {
        waitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.waitForCompletion()
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let account):
                self.finish(with: .completed(account))
            case .failure(let error):
                self.finish(with: .failed(error))
            }
        }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(request.userCode, forType: .string)
        statusText = request.copiedStatusText
        panel.contentView = NSHostingView(rootView: makeView())
    }

    private func openBrowser() {
        NSWorkspace.shared.open(request.promptURL)
        statusText = request.browserOpenedStatusText
        panel.contentView = NSHostingView(rootView: makeView())
    }

    private func cancel() {
        onCancel()
        finish(with: .cancelled)
    }

    private func finish(with result: MenuBarAddAccountSignInPanelResult) {
        guard let completion, !isFinishing else { return }
        self.completion = nil
        waitTask?.cancel()
        isFinishing = true
        panel.makeFirstResponder(nil)
        panel.endEditing(for: nil)
        panel.close()
        panel.orderOut(nil)
        isFinishing = false
        completion.resume(returning: result)
    }
}

@MainActor
private final class MenuBarHostSetupPanelController: NSObject, NSWindowDelegate {
    private let request: MenuBarHostSetupPanelRequest
    private let appIconSource: AppIconSource
    private let model: MenuBarHostSetupPanelModel
    private let onPresented: () -> Void
    private let onCancelled: () -> Void

    private var completion: CheckedContinuation<RemoteHost?, Never>?
    private var isFinishing = false

    private lazy var panel: NSPanel = {
        let panel = makePanel(title: self.request.messageText, size: NSSize(width: 520, height: 274), appIconSource: self.appIconSource)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: self.makeView())
        return panel
    }()

    init(
        request: MenuBarHostSetupPanelRequest,
        appIconSource: AppIconSource,
        testConnection: @escaping (RemoteHost) async -> Result<Void, Error>,
        onPresented: @escaping () -> Void,
        onCancelled: @escaping () -> Void,
        onValidationStarted: @escaping (RemoteHost) -> Void,
        onValidationFinished: @escaping (RemoteHost, Result<Void, Error>) -> Void
    ) {
        self.request = request
        self.appIconSource = appIconSource
        self.model = MenuBarHostSetupPanelModel(
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

    private func makeView() -> MenuBarHostSetupPanelView {
        MenuBarHostSetupPanelView(
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
private final class MenuBarHostSetupPanelModel: ObservableObject {
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

private struct MenuBarAddAccountSignInPanelView: View {
    let request: MenuBarAddAccountSignInPanelRequest
    @Binding var statusText: String
    let onCopy: () -> Void
    let onOpenBrowser: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.informativeText)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            Text(request.userCode)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                )
                .textSelection(.enabled)

            Text(statusText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Spacer()
                Button(request.cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(request.copyTitle, action: onCopy)
                Button(request.openBrowserTitle, action: onOpenBrowser)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(width: 500)
    }
}

private struct MenuBarHostSetupPanelView: View {
    private enum Field {
        case destination
    }

    let request: MenuBarHostSetupPanelRequest
    @ObservedObject var model: MenuBarHostSetupPanelModel
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
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(request.fieldTitle)
                    .font(.system(size: 13, weight: .semibold))
                TextField(request.placeholder, text: $model.destination)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .focused($focusedField, equals: .destination)
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

@MainActor
private func makePanel(title: String, size: NSSize, appIconSource: AppIconSource) -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    panel.title = title
    panel.isReleasedWhenClosed = false
    panel.level = .modalPanel
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.documentIconButton)?.image = appIconSource.appIconImage()
    return panel
}
