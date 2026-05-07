import Foundation
import os
import SealRecorder

private let accountSealProofRecorderLogger = Logger(
    subsystem: "com.raphhgg.codexpill",
    category: "SealValidation"
)

@MainActor
final class AccountSealProofRecorder: AccountValidationRecorder {
    private let scenario: AccountSealScenario
    private let session: CodexPillSealProofSession
    private var didRecordAccountBefore = false

    init(scenario: AccountSealScenario, outputDirectory: URL) throws {
        self.scenario = scenario
        self.session = try CodexPillSealProofSession(
            feature: try AccountSealScenarioCatalog.feature(scenarios: [scenario]),
            scenarioID: scenario.id,
            outputDirectory: outputDirectory
        )
    }

    func recordAddAccountMenuAction(activeAccount: CodexAccount?, savedAccounts: [CodexAccount]) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "menu_action_dispatched",
                step: "menu_action_dispatch",
                invariantIds: [scenario.nameDialogPresentedID],
                payload: [
                    "action": .string(scenario.menuAction),
                    "activeAccountId": .string(activeAccount?.id.uuidString ?? "")
                ]
            )
            try recordAccountBeforeIfNeeded(activeAccount: activeAccount, savedAccounts: savedAccounts)
        } catch {
            accountSealProofRecorderLogger.error("Failed to record Seal add-account action proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordAddAccountNameDialogPresented(runningCLISessions: Int) {
        recordNameDialogPresented(additionalPayload: [
            "runningCLISessions": .int(runningCLISessions)
        ])
    }

    func recordAddAccountNameDialogCancelled(activeAccount: CodexAccount?, savedAccounts: [CodexAccount]) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                scenario.cancelledEventName,
                step: scenario.dialogStep,
                invariantIds: [scenario.nameDialogCancelledID, scenario.cancelKeepsAccountStateID],
                payload: [
                    "dialogId": .string(scenario.dialogID),
                    "activeAccountId": .string(activeAccount?.id.uuidString ?? "")
                ]
            )
            try session.recordSnapshot(
                id: EvidenceID("name_dialog_snapshot"),
                path: "evidence/name-dialog-snapshot.json",
                value: AccountSealNameDialogSnapshot(
                    dialogId: scenario.dialogID,
                    title: scenario.dialogTitle,
                    wasPresented: true,
                    finalState: "cancelled"
                )
            )
            try session.recordSnapshot(
                id: EvidenceID("account_after"),
                path: "evidence/account-after.json",
                value: AccountSealAccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
            )
            try session.finish()
        } catch {
            accountSealProofRecorderLogger.error("Failed to finish Seal name dialog proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordSwitchAccountMenuAction(
        targetAccount: CodexAccount,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "menu_action_dispatched",
                step: "menu_action_dispatch",
                invariantIds: scenario.switchInvariantIDs,
                payload: [
                    "action": .string("switchAccount"),
                    "targetName": .string(targetAccount.name),
                    "targetAccountId": .string(targetAccount.id.uuidString),
                    "activeAccountId": .string(activeAccount?.id.uuidString ?? "")
                ]
            )
            try recordAccountBeforeIfNeeded(activeAccount: activeAccount, savedAccounts: savedAccounts)
        } catch {
            accountSealProofRecorderLogger.error("Failed to record Seal switch-account menu action proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordSwitchConfirmationPresented(targetAccount: CodexAccount) {
        recordSwitchEvent("switch_confirmation_presented", step: "switch_confirmation", targetAccount: targetAccount)
    }

    func recordSwitchConfirmationAccepted(targetAccount: CodexAccount) {
        recordSwitchEvent("switch_confirmation_accepted", step: "switch_confirmation", targetAccount: targetAccount)
    }

    func recordSwitchWorkflowStarted(targetAccount: CodexAccount) {
        recordSwitchEvent("switch_workflow_started", step: "switch_workflow_start", targetAccount: targetAccount)
    }

    func recordCodexRelaunchRequested(targetAccount: CodexAccount) {
        recordSwitchEvent("codex_relaunch_requested", step: "codex_relaunch", targetAccount: targetAccount)
    }

    func recordPostSwitchRefreshCompleted(
        targetAccount: CodexAccount,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "post_switch_refresh_completed",
                step: "post_switch_refresh",
                invariantIds: scenario.switchInvariantIDs,
                payload: [
                    "targetName": .string(targetAccount.name),
                    "targetAccountId": .string(targetAccount.id.uuidString),
                    "activeAccountId": .string(activeAccount?.id.uuidString ?? "")
                ]
            )
            try session.recordSnapshot(
                id: EvidenceID("post_switch_refresh"),
                path: "evidence/post-switch-refresh.json",
                value: AccountSealPostSwitchRefreshEvidence(
                    targetAccount: targetAccount,
                    activeAccount: activeAccount,
                    savedAccounts: savedAccounts
                )
            )
            try session.finish()
        } catch {
            accountSealProofRecorderLogger.error("Failed to finish Seal post-switch refresh proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordActiveAccountChanged(
        fromName: String?,
        toName: String,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "active_account_changed",
                step: "active_account_change",
                invariantIds: scenario.switchInvariantIDs,
                payload: [
                    "fromName": .string(fromName ?? ""),
                    "toName": .string(toName)
                ]
            )
            try session.recordSnapshot(
                id: EvidenceID("account_after"),
                path: "evidence/account-after.json",
                value: AccountSealAccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
            )
        } catch {
            accountSealProofRecorderLogger.error("Failed to record Seal active-account-change proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordScheduledRefreshRequested(
        accountName: String,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "scheduled_refresh_requested",
                step: "scheduled_refresh_request",
                invariantIds: scenario.scheduledRefreshInvariantIDs,
                payload: ["accountName": .string(accountName)]
            )
            try recordAccountBeforeIfNeeded(activeAccount: activeAccount, savedAccounts: savedAccounts)
        } catch {
            accountSealProofRecorderLogger.error("Failed to record Seal scheduled-refresh request proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordScheduledRefreshResult(
        accountName: String,
        error: String?,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount],
        uiEvidence: AccountSealScheduledRefreshUIEvidence
    ) {
        guard !session.isFinished else { return }
        do {
            if let error {
                try session.recordEvent(
                    "scheduled_refresh_failed",
                    step: "scheduled_refresh_result",
                    invariantIds: scenario.scheduledRefreshInvariantIDs,
                    payload: [
                        "accountName": .string(accountName),
                        "error": .string(error)
                    ]
                )
                return
            }

            try session.recordEvent(
                "scheduled_refresh_completed",
                step: "scheduled_refresh_result",
                invariantIds: scenario.scheduledRefreshInvariantIDs,
                payload: ["accountName": .string(accountName)]
            )
            try session.recordSnapshot(
                id: EvidenceID("account_after"),
                path: "evidence/account-after.json",
                value: AccountSealAccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
            )
            try session.recordSnapshot(
                id: EvidenceID("ui_after_refresh"),
                path: "evidence/ui-after-refresh.json",
                value: uiEvidence
            )
            try session.finish()
        } catch {
            accountSealProofRecorderLogger.error("Failed to finish Seal scheduled-refresh proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelIfUnfinished() {
        session.cancelIfUnfinished()
    }

    private func recordAccountBeforeIfNeeded(activeAccount: CodexAccount?, savedAccounts: [CodexAccount]) throws {
        guard !didRecordAccountBefore else { return }
        try session.recordSnapshot(
            id: EvidenceID("account_before"),
            path: "evidence/account-before.json",
            value: AccountSealAccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
        )
        didRecordAccountBefore = true
    }

    private func recordNameDialogPresented(additionalPayload: JSONObject) {
        guard !session.isFinished else { return }
        var payload: JSONObject = [
            "dialogId": .string(scenario.dialogID),
            "title": .string(scenario.dialogTitle)
        ]
        for (key, value) in additionalPayload {
            payload[key] = value
        }
        do {
            try session.recordEvent(
                scenario.presentedEventName,
                step: scenario.dialogStep,
                invariantIds: [scenario.nameDialogPresentedID],
                payload: payload
            )
        } catch {
            accountSealProofRecorderLogger.error("Failed to record Seal name dialog presentation proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordSwitchEvent(_ eventName: String, step: String, targetAccount: CodexAccount) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                eventName,
                step: step,
                invariantIds: scenario.switchInvariantIDs,
                payload: [
                    "targetName": .string(targetAccount.name),
                    "targetAccountId": .string(targetAccount.id.uuidString)
                ]
            )
        } catch {
            accountSealProofRecorderLogger.error("Failed to record Seal switch-account event proof: \(error.localizedDescription, privacy: .public)")
        }
    }
}
