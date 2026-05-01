import AppKit
import SwiftUI

@MainActor
final class CodexSignInPanelController: NSObject, NSWindowDelegate {
    private let request: MenuBarAddAccountSignInPanelRequest
    private let panelWindowFactory: PanelWindowFactory
    private let waitForCompletion: () async -> Result<CodexAccount, Error>
    private let onCancel: () -> Void

    private var completion: CheckedContinuation<MenuBarAddAccountSignInPanelResult, Never>?
    private var waitTask: Task<Void, Never>?
    private var isFinishing = false
    private var statusText: String

    private lazy var panel: NSPanel = {
        let panel = panelWindowFactory.makePanel(
            title: self.request.messageText,
            size: NSSize(width: 500, height: 244)
        )
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: self.makeView())
        return panel
    }()

    init(
        request: MenuBarAddAccountSignInPanelRequest,
        panelWindowFactory: PanelWindowFactory,
        waitForCompletion: @escaping () async -> Result<CodexAccount, Error>,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.panelWindowFactory = panelWindowFactory
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

    private func makeView() -> CodexSignInPanel {
        let fallbackStatusText = request.waitingStatusText
        return CodexSignInPanel(
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

private struct CodexSignInPanel: View {
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

            PanelValueBox(value: request.userCode)

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
