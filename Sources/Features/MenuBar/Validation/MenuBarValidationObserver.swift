import AppKit
import OSLog

private let menuBarValidationObserverLogger = Logger(
    subsystem: "com.raphhgg.codexpill",
    category: "MenuBarValidationObserver"
)

@MainActor
final class MenuBarValidationObserver {
    private static let liveProofLayer = "live_ui"
    private static let hoverInvariantIDs = ["menubar.text_on_hover.stays_visible_inside_resized_bounds"]
    private static let shortcutRevealInvariantIDs = ["status_bar.reveal_shortcut.temporarily_shows_label"]
    private static let switchInvariantIDs = ["accounts.switch_account.menu_action_changes_active_account"]
    private static let addAccountNameDialogInvariantIDs = [
        "accounts.add_account.name_dialog_presented",
        "accounts.add_account.name_dialog_cancelled",
        "accounts.add_account.cancel_keeps_account_state"
    ]
    private static let scheduledRefreshInvariantIDs = ["accounts.scheduled_refresh.requested_and_completed"]

    private let sink: MenuBarValidationSink?
    private let scenario: String?

    private var lastMenuAction: String?
    private var lastSwitchTargetName: String?
    private var lastConfirmationRequest: String?
    private var lastConfirmationAccepted: Bool?
    private var pendingSwitchTargetID: UUID?
    private var pendingSwitchTargetName: String?

    init(
        sink: MenuBarValidationSink? = nil,
        scenario: String? = MenuBarValidationConfiguration.scenario()
    ) {
        self.sink = sink
        self.scenario = scenario
    }

    func cancelIfUnfinished() {
    }

    func recordSnapshot(
        state: MenuBarMenuState,
        menu: NSMenu?,
        statusItemState: StatusItemRuntimeSnapshot?
    ) {
        guard let sink else { return }

        do {
            try sink.record(
                MenuBarValidationSupport.makeSnapshot(
                    state: state,
                    menu: menu,
                    statusItemState: statusItemState,
                    actionTrace: .init(
                        lastMenuAction: lastMenuAction,
                        lastSwitchTargetName: lastSwitchTargetName,
                        lastConfirmationRequest: lastConfirmationRequest,
                        lastConfirmationAccepted: lastConfirmationAccepted
                    )
                )
            )
        } catch {
            menuBarValidationObserverLogger.error("Failed to record validation snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordMenuAction(
        _ name: String,
        payload: [String: String] = [:],
        state: MenuBarMenuState,
        menu: NSMenu?,
        statusItemState: StatusItemRuntimeSnapshot?
    ) {
        lastMenuAction = name
        recordEvent(
            "menu_action_dispatched",
            step: "menu_action_dispatch",
            payload: ["action": name].merging(payload, uniquingKeysWith: { _, new in new })
        )
        recordSnapshot(state: state, menu: menu, statusItemState: statusItemState)
    }

    func recordMenuOpened(menuItemCount: Int) {
        recordEvent(
            "menu_opened",
            step: "menu_open",
            payload: ["menuItemCount": String(menuItemCount)]
        )
    }

    func recordAddAccountMenuAction(activeAccount: CodexAccount?, savedAccounts: [CodexAccount]) {
    }

    func recordAddAccountPromptPresented(runningCLISessions: Int) {
        recordEvent(
            "add_account_prompt_presented",
            step: "add_account_prompt",
            invariantIds: Self.addAccountNameDialogInvariantIDs
        )
    }

    func recordAddAccountPromptCancelled(activeAccount: CodexAccount?, savedAccounts: [CodexAccount]) {
        recordEvent(
            "add_account_prompt_cancelled",
            step: "add_account_prompt",
            invariantIds: Self.addAccountNameDialogInvariantIDs
        )
    }

    func recordAddAccountPromptConfirmed(enteredName: String) {
        recordEvent(
            "add_account_prompt_confirmed",
            step: "add_account_prompt",
            invariantIds: Self.addAccountNameDialogInvariantIDs,
            payload: ["enteredName": enteredName]
        )
    }

    func recordSwitchAccountMenuAction(
        targetAccount: CodexAccount,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        lastSwitchTargetName = targetAccount.name
    }

    func recordSwitchConfirmationPresented(targetAccount: CodexAccount) {
        lastConfirmationRequest = "switchAccount"
        recordEvent(
            "switch_confirmation_presented",
            step: "switch_confirmation",
            payload: ["targetName": targetAccount.name]
        )
    }

    func recordSwitchConfirmationResult(accepted: Bool, targetAccount: CodexAccount) {
        lastConfirmationAccepted = accepted
        recordEvent(
            accepted ? "switch_confirmation_accepted" : "switch_confirmation_cancelled",
            step: "switch_confirmation",
            payload: ["targetName": targetAccount.name]
        )
    }

    func recordSwitchWorkflowStarted(targetAccount: CodexAccount) {
        pendingSwitchTargetID = targetAccount.id
        pendingSwitchTargetName = targetAccount.name
        recordEvent(
            "switch_workflow_started",
            step: "switch_workflow_start",
            invariantIds: Self.switchInvariantIDs,
            payload: ["targetName": targetAccount.name]
        )
    }

    func recordCodexRelaunchRequested(targetAccount: CodexAccount) {
        recordEvent(
            "codex_relaunch_requested",
            step: "codex_relaunch",
            invariantIds: Self.switchInvariantIDs,
            payload: ["targetName": targetAccount.name]
        )
    }

    func recordPostSwitchRefreshCompleted(
        targetAccount: CodexAccount,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        recordEvent(
            "post_switch_refresh_completed",
            step: "post_switch_refresh",
            invariantIds: Self.switchInvariantIDs,
            payload: [
                "targetName": targetAccount.name,
                "activeAccountId": activeAccount?.id.uuidString ?? ""
            ]
        )
    }

    func clearPendingSwitchIfTargetDidNotActivate(targetID: UUID, activeAccountID: UUID?) {
        guard pendingSwitchTargetID == targetID, activeAccountID != targetID else { return }
        pendingSwitchTargetID = nil
        pendingSwitchTargetName = nil
    }

    func recordActiveAccountTransitionIfNeeded(
        previousName: String?,
        currentID: UUID?,
        currentName: String?,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) -> Bool {
        guard let targetID = pendingSwitchTargetID, currentID == targetID else {
            return false
        }

        let toName = currentName ?? pendingSwitchTargetName ?? ""
        recordEvent(
            "active_account_changed",
            step: "active_account_change",
            invariantIds: Self.switchInvariantIDs,
            payload: [
                "fromName": previousName ?? "",
                "toName": toName
            ]
        )
        pendingSwitchTargetID = nil
        pendingSwitchTargetName = nil
        return true
    }

    func recordScheduledRefreshRequested(
        accountName: String,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        recordEvent(
            "scheduled_refresh_requested",
            step: "scheduled_refresh_request",
            invariantIds: Self.scheduledRefreshInvariantIDs,
            payload: ["accountName": accountName]
        )
    }

    func recordScheduledRefreshResult(
        accountName: String,
        error: String?,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount],
        menuSnapshot: MenuBarValidationSnapshot
    ) {
        if let error {
            recordEvent(
                "scheduled_refresh_failed",
                step: "scheduled_refresh_result",
                invariantIds: Self.scheduledRefreshInvariantIDs,
                payload: [
                    "accountName": accountName,
                    "error": error
                ]
            )
        } else {
            recordEvent(
                "scheduled_refresh_completed",
                step: "scheduled_refresh_result",
                invariantIds: Self.scheduledRefreshInvariantIDs,
                payload: ["accountName": accountName]
            )
        }
    }

    func recordStatusItemRuntimeEvent(_ event: StatusItemRuntime.Event) {
        switch event {
        case .hoverEntered:
            recordEvent("status_item_hover_entered", step: "hover_enter", invariantIds: Self.hoverInvariantIDs)
        case .hoverExitScheduled:
            recordEvent("status_item_hover_exit_scheduled", step: "hover_exit_schedule", invariantIds: Self.hoverInvariantIDs)
        case .hoverExited:
            recordEvent("status_item_hover_exited", step: "hover_exit", invariantIds: Self.hoverInvariantIDs)
        case .shortcutRevealStarted:
            recordEvent("status_item_shortcut_reveal_started", step: "shortcut_reveal_start", invariantIds: Self.shortcutRevealInvariantIDs)
        case .shortcutRevealEnded:
            recordEvent("status_item_shortcut_reveal_ended", step: "shortcut_reveal_end", invariantIds: Self.shortcutRevealInvariantIDs)
        case .titleBecameVisible(let displayedTitle):
            recordEvent(
                "status_item_title_became_visible",
                step: "hover_title_visible",
                invariantIds: Self.hoverInvariantIDs,
                payload: ["displayedTitle": displayedTitle ?? ""]
            )
        case .titleHidden:
            recordEvent("status_item_title_hidden", step: "hover_title_hidden", invariantIds: Self.hoverInvariantIDs)
        }
    }

    private func recordEvent(
        _ name: String,
        step: String,
        invariantIds: [String] = [],
        payload: [String: String] = [:]
    ) {
        guard let sink, let scenario else { return }

        do {
            try sink.record(
                MenuBarValidationEvent(
                    scenario: scenario,
                    proofLayer: Self.liveProofLayer,
                    invariantIds: invariantIds,
                    event: name,
                    step: step,
                    payload: sanitizedValidationPayload(payload)
                )
            )
        } catch {
            menuBarValidationObserverLogger.error("Failed to record validation event: \(error.localizedDescription, privacy: .public)")
        }
    }
}
