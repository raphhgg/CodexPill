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

    func recordSwitchAccount(targetAccountID: UUID) {
        record(DiagnosticWorkflowEvent(
            name: "switch_account",
            category: .switchAccount,
            fields: [.account(targetAccountID, redaction: .accountAlias)]
        ))
    }

    func recordRemoteHostSwitch(targetAccountID: UUID, hostDestination: String) {
        record(DiagnosticWorkflowEvent(
            name: "switch_account_on_host",
            category: .switchAccount,
            fields: [
                .account(targetAccountID, redaction: .accountAlias),
                .hostDestination(hostDestination, redaction: .hostAlias)
            ]
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
        case "addAccount":
            return "add_account"
        case "removeAccount":
            return "remove_account"
        case "addHost":
            return "add_host"
        case "switchAccount":
            return "switch_account_menu"
        case "enableNotifications", "toggleNotificationsWhenBlocked", "toggleNotificationsWhenOut":
            return "notification_setting_changed"
        default:
            return "menu_action"
        }
    }

    private func category(forMenuAction name: String) -> DiagnosticEventCategory {
        switch name {
        case "addAccount":
            return .addAccount
        case "removeAccount":
            return .removeAccount
        case "addHost":
            return .addHost
        case "switchAccount":
            return .switchAccount
        case "enableNotifications", "toggleNotificationsWhenBlocked", "toggleNotificationsWhenOut":
            return .notificationEvaluation
        default:
            return .menuAction
        }
    }
}
