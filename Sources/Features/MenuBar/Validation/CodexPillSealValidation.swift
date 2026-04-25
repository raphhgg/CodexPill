import Foundation
import os
import SealRecorder

private let codexPillSealValidationLogger = Logger(
    subsystem: "com.raphhgg.codexpill",
    category: "SealValidation"
)

enum CodexPillSealValidationConfiguration {
    static let proofOutputPathEnvironmentKey = "CODEXPILL_SEAL_PROOF_OUTPUT"

    @MainActor
    static func makeRun(environment: [String: String] = ProcessInfo.processInfo.environment) -> CodexPillSealValidationRun? {
        guard let legacyScenario = MenuBarValidationConfiguration.scenario(environment: environment),
              let scenario = CodexPillSealScenario(legacyScenario: legacyScenario),
              let proofOutputPath = environment[proofOutputPathEnvironmentKey],
              !proofOutputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return try? CodexPillSealValidationRun(
            scenario: scenario,
            outputDirectory: URL(fileURLWithPath: proofOutputPath)
        )
    }
}

@MainActor
final class CodexPillSealValidationRun {
    private let scenario: CodexPillSealScenario
    private let run: SealRun
    private var didRecordAccountBefore = false
    private var didFinish = false

    convenience init(outputDirectory: URL) throws {
        try self.init(scenario: .saveCurrentAccountNameDialogCancelled, outputDirectory: outputDirectory)
    }

    fileprivate init(scenario: CodexPillSealScenario, outputDirectory: URL) throws {
        self.scenario = scenario
        try SealRecorder.register(features: [Self.feature(scenarios: [scenario])])
        run = try SealRecorder.startRun(
            feature: scenario.featureID,
            scenario: scenario.id,
            executionMode: .liveUI,
            outputDirectory: outputDirectory
        )
    }

    func recordSaveCurrentAccountMenuAction(
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                "menu_action_dispatched",
                step: "menu_action_dispatch",
                invariantIds: [scenario.nameDialogPresentedID],
                payload: [
                    "action": .string(scenario.menuAction),
                    "activeAccountId": .string(activeAccount?.id.uuidString ?? "")
                ]
            )
            if !didRecordAccountBefore {
                try run.recordSnapshot(
                    id: EvidenceID("account_before"),
                    path: "evidence/account-before.json",
                    value: AccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
                )
                didRecordAccountBefore = true
            }
        } catch {
            codexPillSealValidationLogger.error("Failed to record Seal menu action proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordSaveCurrentAccountNameDialogPresented(activeAccountEmail: String?) {
        guard !didFinish else { return }
        recordNameDialogPresented(additionalPayload: [
            "activeAccountEmail": .string(activeAccountEmail ?? "")
        ])
    }

    func recordSaveCurrentAccountNameDialogCancelled(
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        recordNameDialogCancelled(activeAccount: activeAccount, savedAccounts: savedAccounts)
    }

    func recordAddAccountMenuAction(
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                "menu_action_dispatched",
                step: "menu_action_dispatch",
                invariantIds: [scenario.nameDialogPresentedID],
                payload: [
                    "action": .string(scenario.menuAction),
                    "activeAccountId": .string(activeAccount?.id.uuidString ?? "")
                ]
            )
            if !didRecordAccountBefore {
                try run.recordSnapshot(
                    id: EvidenceID("account_before"),
                    path: "evidence/account-before.json",
                    value: AccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
                )
                didRecordAccountBefore = true
            }
        } catch {
            codexPillSealValidationLogger.error("Failed to record Seal add-account action proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordAddAccountNameDialogPresented(runningCLISessions: Int) {
        guard !didFinish else { return }
        recordNameDialogPresented(additionalPayload: [
            "runningCLISessions": .int(runningCLISessions)
        ])
    }

    func recordAddAccountNameDialogCancelled(
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        recordNameDialogCancelled(activeAccount: activeAccount, savedAccounts: savedAccounts)
    }

    func recordSwitchAccountMenuAction(
        targetAccount: CodexAccount,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
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
            if !didRecordAccountBefore {
                try run.recordSnapshot(
                    id: EvidenceID("account_before"),
                    path: "evidence/account-before.json",
                    value: AccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
                )
                didRecordAccountBefore = true
            }
        } catch {
            codexPillSealValidationLogger.error("Failed to record Seal switch-account menu action proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordSwitchConfirmationPresented(targetAccount: CodexAccount) {
        recordSwitchEvent(
            "switch_confirmation_presented",
            step: "switch_confirmation",
            targetAccount: targetAccount
        )
    }

    func recordSwitchConfirmationAccepted(targetAccount: CodexAccount) {
        recordSwitchEvent(
            "switch_confirmation_accepted",
            step: "switch_confirmation",
            targetAccount: targetAccount
        )
    }

    func recordSwitchWorkflowStarted(targetAccount: CodexAccount) {
        recordSwitchEvent(
            "switch_workflow_started",
            step: "switch_workflow_start",
            targetAccount: targetAccount
        )
    }

    func recordActiveAccountChanged(
        fromName: String?,
        toName: String,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                "active_account_changed",
                step: "active_account_change",
                invariantIds: scenario.switchInvariantIDs,
                payload: [
                    "fromName": .string(fromName ?? ""),
                    "toName": .string(toName)
                ]
            )
            try run.recordSnapshot(
                id: EvidenceID("account_after"),
                path: "evidence/account-after.json",
                value: AccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
            )
            try run.finish()
            didFinish = true
        } catch {
            codexPillSealValidationLogger.error("Failed to finish Seal switch-account proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordAddHostMenuAction() {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                "menu_action_dispatched",
                step: "menu_action_dispatch",
                invariantIds: scenario.hostInvariantIDs,
                payload: [
                    "action": .string("addHost")
                ]
            )
        } catch {
            codexPillSealValidationLogger.error("Failed to record Seal add-host menu action proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordAddHostSetupPresented() {
        recordHostEvent(
            "add_host_setup_presented",
            step: "add_host_setup"
        )
    }

    func recordAddHostValidationStarted(hostName: String) {
        recordHostEvent(
            "add_host_validation_started",
            step: "add_host_validation",
            payload: ["hostName": .string(hostName)]
        )
    }

    func recordAddHostValidationFailed(hostName: String, message: String) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                "add_host_validation_failed",
                step: "add_host_validation",
                invariantIds: scenario.hostInvariantIDs,
                payload: [
                    "hostName": .string(hostName),
                    "message": .string(message)
                ]
            )
            try run.finish()
            didFinish = true
        } catch {
            codexPillSealValidationLogger.error("Failed to finish Seal add-host validation proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelIfUnfinished() {
        guard !didFinish else { return }
        run.cancelIfUnfinished()
        didFinish = true
    }

    private func recordNameDialogPresented(additionalPayload: JSONObject) {
        guard !didFinish else { return }
        var payload: JSONObject = [
            "dialogId": .string(scenario.dialogID),
            "title": .string(scenario.dialogTitle)
        ]
        for (key, value) in additionalPayload {
            payload[key] = value
        }
        do {
            try run.recordEvent(
                scenario.presentedEventName,
                step: scenario.dialogStep,
                invariantIds: [scenario.nameDialogPresentedID],
                payload: payload
            )
        } catch {
            codexPillSealValidationLogger.error("Failed to record Seal name dialog presentation proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordNameDialogCancelled(
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                scenario.cancelledEventName,
                step: scenario.dialogStep,
                invariantIds: [scenario.nameDialogCancelledID, scenario.cancelKeepsAccountStateID],
                payload: [
                    "dialogId": .string(scenario.dialogID),
                    "activeAccountId": .string(activeAccount?.id.uuidString ?? "")
                ]
            )
            try run.recordSnapshot(
                id: EvidenceID("name_dialog_snapshot"),
                path: "evidence/name-dialog-snapshot.json",
                value: NameDialogSnapshot(
                    dialogId: scenario.dialogID,
                    title: scenario.dialogTitle,
                    wasPresented: true,
                    finalState: "cancelled"
                )
            )
            try run.recordSnapshot(
                id: EvidenceID("account_after"),
                path: "evidence/account-after.json",
                value: AccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
            )
            try run.finish()
            didFinish = true
        } catch {
            codexPillSealValidationLogger.error("Failed to finish Seal name dialog proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordSwitchEvent(_ eventName: String, step: String, targetAccount: CodexAccount) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                eventName,
                step: step,
                invariantIds: scenario.switchInvariantIDs,
                payload: [
                    "targetName": .string(targetAccount.name),
                    "targetAccountId": .string(targetAccount.id.uuidString)
                ]
            )
        } catch {
            codexPillSealValidationLogger.error("Failed to record Seal switch-account event proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordHostEvent(_ eventName: String, step: String, payload: JSONObject = [:]) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                eventName,
                step: step,
                invariantIds: scenario.hostInvariantIDs,
                payload: payload
            )
        } catch {
            codexPillSealValidationLogger.error("Failed to record Seal add-host event proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func feature(scenarios: [CodexPillSealScenario]) throws -> SealFeature {
        try SealFeature(
            id: scenarios.first?.featureID ?? FeatureID("accounts"),
            scenarios: try scenarios.map(makeScenario)
        )
    }

    private static func makeScenario(_ scenario: CodexPillSealScenario) throws -> SealScenario {
        if let hostValidationID = scenario.hostValidationID,
           let hostExpectation = scenario.hostExpectation {
            return try SealScenario(
                id: scenario.id,
                scenarioType: .failurePath,
                supportedExecutionModes: [.liveUI],
                expectations: [
                    try SealExpectation(
                        text: hostExpectation,
                        invariants: [
                            SealInvariantRef(
                                id: hostValidationID,
                                requiredEvidence: [
                                    EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream)
                                ],
                                rule: scenario.hostValidationRule
                            )
                        ]
                    )
                ]
            )
        }

        if let switchChangesActiveAccountID = scenario.switchChangesActiveAccountID,
           let switchExpectation = scenario.switchExpectation {
            return try SealScenario(
                id: scenario.id,
                scenarioType: .happyPath,
                supportedExecutionModes: [.liveUI],
                expectations: [
                    try SealExpectation(
                        text: switchExpectation,
                        invariants: [
                            SealInvariantRef(
                                id: switchChangesActiveAccountID,
                                requiredEvidence: [
                                    EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                    EvidenceRequirement(id: EvidenceID("account_before"), kind: .snapshot),
                                    EvidenceRequirement(id: EvidenceID("account_after"), kind: .snapshot)
                                ],
                                rule: scenario.switchChangesActiveAccountRule
                            )
                        ]
                    )
                ]
            )
        }

        return try SealScenario(
            id: scenario.id,
            scenarioType: .failurePath,
            supportedExecutionModes: [.liveUI],
            expectations: [
                try SealExpectation(
                    text: scenario.presentedAndCancelledExpectation,
                    invariants: [
                        SealInvariantRef(
                            id: scenario.nameDialogPresentedID,
                            requiredEvidence: [
                                EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                EvidenceRequirement(id: EvidenceID("name_dialog_snapshot"), kind: .snapshot)
                            ],
                            rule: scenario.nameDialogPresentedRule
                        ),
                        SealInvariantRef(
                            id: scenario.nameDialogCancelledID,
                            requiredEvidence: [
                                EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                EvidenceRequirement(id: EvidenceID("name_dialog_snapshot"), kind: .snapshot)
                            ],
                            rule: scenario.nameDialogCancelledRule
                        )
                    ]
                ),
                try SealExpectation(
                    text: scenario.nonMutatingExpectation,
                    invariants: [
                        SealInvariantRef(
                            id: scenario.cancelKeepsAccountStateID,
                            requiredEvidence: [
                                EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                EvidenceRequirement(id: EvidenceID("account_before"), kind: .snapshot),
                                EvidenceRequirement(id: EvidenceID("account_after"), kind: .snapshot)
                            ],
                            rule: scenario.cancelKeepsAccountStateRule
                        )
                    ]
                )
            ]
        )
    }
}

private struct CodexPillSealScenario {
    private static let addHostValidationDestination = "codexpill-validation.invalid"

    let featureID: FeatureID
    let id: ScenarioID
    let menuAction: String
    let dialogID: String
    let dialogTitle: String
    let dialogStep: String
    let presentedEventName: String
    let cancelledEventName: String
    let nameDialogPresentedID: InvariantID
    let nameDialogCancelledID: InvariantID
    let cancelKeepsAccountStateID: InvariantID
    let switchChangesActiveAccountID: InvariantID?
    let hostValidationID: InvariantID?
    let presentedAndCancelledExpectation: String
    let nonMutatingExpectation: String
    let switchExpectation: String?
    let hostExpectation: String?

    var switchInvariantIDs: [InvariantID] {
        switchChangesActiveAccountID.map { [$0] } ?? []
    }

    var hostInvariantIDs: [InvariantID] {
        hostValidationID.map { [$0] } ?? []
    }

    var nameDialogPresentedRule: SealRule {
        .all([
            .eventSequence([
                EventExpectation("menu_action_dispatched", payload: [
                    "action": .string(menuAction)
                ]),
                EventExpectation(presentedEventName, payload: [
                    "dialogId": .string(dialogID)
                ])
            ]),
            .snapshotEquals(
                SnapshotEqualsRule(
                    evidence: EvidenceID("name_dialog_snapshot"),
                    path: "wasPresented",
                    value: .bool(true)
                )
            )
        ])
    }

    var nameDialogCancelledRule: SealRule {
        .all([
            .eventSequence([
                EventExpectation(presentedEventName, payload: [
                    "dialogId": .string(dialogID)
                ]),
                EventExpectation(cancelledEventName, payload: [
                    "dialogId": .string(dialogID)
                ])
            ]),
            .snapshotEquals(
                SnapshotEqualsRule(
                    evidence: EvidenceID("name_dialog_snapshot"),
                    path: "finalState",
                    value: .string("cancelled")
                )
            )
        ])
    }

    var cancelKeepsAccountStateRule: SealRule {
        .all([
            .eventExists(
                EventExpectation(cancelledEventName, payload: [
                    "dialogId": .string(dialogID)
                ])
            ),
            .snapshotsEqual(
                SnapshotsEqualRule(
                    before: EvidenceID("account_before"),
                    after: EvidenceID("account_after"),
                    paths: ["activeAccountId", "savedAccounts"]
                )
            )
        ])
    }

    var switchChangesActiveAccountRule: SealRule {
        .all([
            .eventSequence([
                EventExpectation("menu_action_dispatched", payload: [
                    "action": .string("switchAccount")
                ]),
                EventExpectation("switch_confirmation_presented"),
                EventExpectation("switch_confirmation_accepted"),
                EventExpectation("switch_workflow_started"),
                EventExpectation("active_account_changed")
            ]),
            .snapshotsDiffer(
                SnapshotsDifferRule(
                    before: EvidenceID("account_before"),
                    after: EvidenceID("account_after"),
                    paths: ["activeAccountId"]
                )
            )
        ])
    }

    var hostValidationRule: SealRule {
        .eventSequence([
            EventExpectation("menu_action_dispatched", payload: [
                "action": .string("addHost")
            ]),
            EventExpectation("add_host_setup_presented"),
            EventExpectation("add_host_validation_started", payload: [
                "hostName": .string(Self.addHostValidationDestination)
            ]),
            EventExpectation("add_host_validation_failed", payload: [
                "hostName": .string(Self.addHostValidationDestination)
            ])
        ])
    }

    private init(
        featureID: FeatureID = FeatureID("accounts"),
        id: ScenarioID,
        menuAction: String,
        dialogID: String,
        dialogTitle: String,
        dialogStep: String,
        presentedEventName: String,
        cancelledEventName: String,
        nameDialogPresentedID: InvariantID,
        nameDialogCancelledID: InvariantID,
        cancelKeepsAccountStateID: InvariantID,
        presentedAndCancelledExpectation: String,
        nonMutatingExpectation: String,
        switchChangesActiveAccountID: InvariantID? = nil,
        switchExpectation: String? = nil,
        hostValidationID: InvariantID? = nil,
        hostExpectation: String? = nil
    ) {
        self.featureID = featureID
        self.id = id
        self.menuAction = menuAction
        self.dialogID = dialogID
        self.dialogTitle = dialogTitle
        self.dialogStep = dialogStep
        self.presentedEventName = presentedEventName
        self.cancelledEventName = cancelledEventName
        self.nameDialogPresentedID = nameDialogPresentedID
        self.nameDialogCancelledID = nameDialogCancelledID
        self.cancelKeepsAccountStateID = cancelKeepsAccountStateID
        self.switchChangesActiveAccountID = switchChangesActiveAccountID
        self.hostValidationID = hostValidationID
        self.presentedAndCancelledExpectation = presentedAndCancelledExpectation
        self.nonMutatingExpectation = nonMutatingExpectation
        self.switchExpectation = switchExpectation
        self.hostExpectation = hostExpectation
    }

    init?(legacyScenario: String) {
        switch legacyScenario {
        case "live-save-current-account-name-dialog-cancelled", "live-save-current-prompt":
            self = .saveCurrentAccountNameDialogCancelled
        case "live-add-account-name-dialog-cancelled", "live-sign-in-another-prompt":
            self = .addAccountNameDialogCancelled
        case "live-account-switch":
            self = .switchAccountChangesActiveAccount
        case "live-add-host-destination-validation-failed", "live-add-host-prompt":
            self = .addHostDestinationValidationFailed
        default:
            return nil
        }
    }

    static let saveCurrentAccountNameDialogCancelled = CodexPillSealScenario(
        id: ScenarioID("save-current-account-name-dialog-cancelled"),
        menuAction: "addCurrentAccount",
        dialogID: "save_current_account_name",
        dialogTitle: "Save Current Account",
        dialogStep: "save_current_account_name_dialog",
        presentedEventName: "save_current_account_name_dialog_presented",
        cancelledEventName: "save_current_account_name_dialog_cancelled",
        nameDialogPresentedID: InvariantID("accounts.save_current_account.name_dialog_presented"),
        nameDialogCancelledID: InvariantID("accounts.save_current_account.name_dialog_cancelled"),
        cancelKeepsAccountStateID: InvariantID("accounts.save_current_account.cancel_keeps_account_state"),
        presentedAndCancelledExpectation: "The Save Current Account name dialog is presented and cancelled",
        nonMutatingExpectation: "Cancelling the Save Current Account name dialog does not create or change a saved account"
    )

    static let addAccountNameDialogCancelled = CodexPillSealScenario(
        id: ScenarioID("add-account-name-dialog-cancelled"),
        menuAction: "addAccount",
        dialogID: "add_account_name",
        dialogTitle: "Add Account",
        dialogStep: "add_account_name_dialog",
        presentedEventName: "add_account_name_dialog_presented",
        cancelledEventName: "add_account_name_dialog_cancelled",
        nameDialogPresentedID: InvariantID("accounts.add_account.name_dialog_presented"),
        nameDialogCancelledID: InvariantID("accounts.add_account.name_dialog_cancelled"),
        cancelKeepsAccountStateID: InvariantID("accounts.add_account.cancel_keeps_account_state"),
        presentedAndCancelledExpectation: "The Add Account name dialog is presented and cancelled",
        nonMutatingExpectation: "Cancelling the Add Account name dialog does not create or change a saved account"
    )

    static let switchAccountChangesActiveAccount = CodexPillSealScenario(
        id: ScenarioID("switch-account-changes-active-account"),
        menuAction: "switchAccount",
        dialogID: "switch_account_confirmation",
        dialogTitle: "Switch Account",
        dialogStep: "switch_confirmation",
        presentedEventName: "switch_confirmation_presented",
        cancelledEventName: "switch_confirmation_cancelled",
        nameDialogPresentedID: InvariantID("accounts.switch_account.confirmation_presented"),
        nameDialogCancelledID: InvariantID("accounts.switch_account.confirmation_cancelled"),
        cancelKeepsAccountStateID: InvariantID("accounts.switch_account.cancel_keeps_account_state"),
        presentedAndCancelledExpectation: "The switch-account confirmation is presented",
        nonMutatingExpectation: "Cancelling the switch-account confirmation does not change account state",
        switchChangesActiveAccountID: InvariantID("accounts.switch_account.menu_action_changes_active_account"),
        switchExpectation: "Switching account through the menubar changes the active account"
    )

    static let addHostDestinationValidationFailed = CodexPillSealScenario(
        featureID: FeatureID("hosts"),
        id: ScenarioID("add-host-destination-validation-failed"),
        menuAction: "addHost",
        dialogID: "add_host_setup",
        dialogTitle: "Add Host",
        dialogStep: "add_host_setup",
        presentedEventName: "add_host_setup_presented",
        cancelledEventName: "add_host_setup_cancelled",
        nameDialogPresentedID: InvariantID("hosts.add_host.setup_presented"),
        nameDialogCancelledID: InvariantID("hosts.add_host.setup_cancelled"),
        cancelKeepsAccountStateID: InvariantID("hosts.add_host.cancel_keeps_host_state"),
        presentedAndCancelledExpectation: "The Add Host setup dialog is presented",
        nonMutatingExpectation: "Cancelling the Add Host setup dialog does not change host state",
        hostValidationID: InvariantID("hosts.add_host.destination_validation_failed"),
        hostExpectation: "Entering an invalid Add Host destination emits validation feedback"
    )
}

private struct AccountStateSnapshot: Encodable {
    let activeAccountId: String?
    let savedAccounts: [SavedAccountSnapshot]

    init(activeAccount: CodexAccount?, savedAccounts: [CodexAccount]) {
        self.activeAccountId = activeAccount?.id.uuidString
        self.savedAccounts = savedAccounts.map(SavedAccountSnapshot.init(account:))
    }
}

private struct SavedAccountSnapshot: Encodable {
    let id: String
    let name: String
    let email: String?

    init(account: CodexAccount) {
        self.id = account.id.uuidString
        self.name = account.name
        self.email = account.email
    }
}

private struct NameDialogSnapshot: Encodable {
    let dialogId: String
    let title: String
    let wasPresented: Bool
    let finalState: String
}
