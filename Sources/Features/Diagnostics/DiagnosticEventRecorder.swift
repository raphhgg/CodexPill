import Foundation

@MainActor
final class DiagnosticEventRecorder {
    private let maximumEventCount: Int
    private var storedEvents: [DiagnosticWorkflowEvent] = []

    init(maximumEventCount: Int = 50) {
        self.maximumEventCount = maximumEventCount
    }

    var events: [DiagnosticWorkflowEvent] {
        storedEvents
    }

    func record(_ event: DiagnosticWorkflowEvent) {
        storedEvents.append(event)
        if storedEvents.count > maximumEventCount {
            storedEvents.removeFirst(storedEvents.count - maximumEventCount)
        }
    }

    func recordMenuAction(_ name: String) {
        record(DiagnosticWorkflowEvent(
            name: diagnosticEventName(forMenuAction: name),
            category: category(forMenuAction: name)
        ))
    }

    func recordRefresh(resultCategory: String) {
        record(DiagnosticWorkflowEvent(
            name: "refresh",
            category: .refresh,
            fields: [.string(name: "result", value: resultCategory, redaction: .resultCategory)]
        ))
    }

    private func diagnosticEventName(forMenuAction name: String) -> String {
        switch name {
        case "signInToCodex":
            return "codex_sign_in"
        case "useSignedInCodexAccount":
            return "codex_account_replaced"
        default:
            return "menu_action"
        }
    }

    private func category(forMenuAction name: String) -> DiagnosticEventCategory {
        switch name {
        case "signInToCodex", "useSignedInCodexAccount":
            return .addAccount
        default:
            return .menuAction
        }
    }
}
