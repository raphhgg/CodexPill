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

    func recordScheduledRefreshRequested(
        accountName: String,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount]
    ) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                "scheduled_refresh_requested",
                step: "scheduled_refresh_request",
                invariantIds: scenario.scheduledRefreshInvariantIDs,
                payload: ["accountName": .string(accountName)]
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
            codexPillSealValidationLogger.error("Failed to record Seal scheduled-refresh request proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordScheduledRefreshResult(
        accountName: String,
        error: String?,
        activeAccount: CodexAccount?,
        savedAccounts: [CodexAccount],
        menuSnapshot: MenuBarValidationSnapshot
    ) {
        guard !didFinish else { return }
        do {
            if let error {
                try run.recordEvent(
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

            try run.recordEvent(
                "scheduled_refresh_completed",
                step: "scheduled_refresh_result",
                invariantIds: scenario.scheduledRefreshInvariantIDs,
                payload: ["accountName": .string(accountName)]
            )
            try run.recordSnapshot(
                id: EvidenceID("account_after"),
                path: "evidence/account-after.json",
                value: AccountStateSnapshot(activeAccount: activeAccount, savedAccounts: savedAccounts)
            )
            try run.recordSnapshot(
                id: EvidenceID("menu_after"),
                path: "evidence/menu-after.json",
                value: ScheduledRefreshMenuEvidence(snapshot: menuSnapshot)
            )
            try run.finish()
            didFinish = true
        } catch {
            codexPillSealValidationLogger.error("Failed to finish Seal scheduled-refresh proof: \(error.localizedDescription, privacy: .public)")
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
            try run.recordSnapshot(
                id: EvidenceID("host_validation_snapshot"),
                path: "evidence/host-validation-snapshot.json",
                value: HostValidationSnapshot(
                    hostName: hostName,
                    validationResult: "failed",
                    message: message
                )
            )
            try run.finish()
            didFinish = true
        } catch {
            codexPillSealValidationLogger.error("Failed to finish Seal add-host validation proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordRemoteHostSwitchMenuAction(targetName: String, hostName: String) {
        recordRemoteHostSwitchEvent(
            "menu_action_dispatched",
            step: "menu_action_dispatch",
            targetName: targetName,
            hostName: hostName,
            additionalPayload: ["action": .string("switchAccountOnHost")]
        )
    }

    func recordRemoteHostSwitchStarted(targetName: String, hostName: String) {
        recordRemoteHostSwitchEvent(
            "remote_host_switch_started",
            step: "remote_host_switch_start",
            targetName: targetName,
            hostName: hostName
        )
    }

    func recordRemoteHostActiveAccountChanged(targetName: String, hostName: String) {
        guard !didFinish else { return }
        do {
            try run.recordEvent(
                "remote_host_active_account_changed",
                step: "remote_host_switch_result",
                invariantIds: scenario.remoteHostSwitchInvariantIDs,
                payload: [
                    "targetName": .string(targetName),
                    "hostName": .string(hostName)
                ]
            )
            try run.finish()
            didFinish = true
        } catch {
            codexPillSealValidationLogger.error("Failed to finish Seal remote-host switch proof: \(error.localizedDescription, privacy: .public)")
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

    private func recordRemoteHostSwitchEvent(
        _ eventName: String,
        step: String,
        targetName: String,
        hostName: String,
        additionalPayload: JSONObject = [:]
    ) {
        guard !didFinish else { return }
        var payload: JSONObject = [
            "targetName": .string(targetName),
            "hostName": .string(hostName)
        ]
        for (key, value) in additionalPayload {
            payload[key] = value
        }
        do {
            try run.recordEvent(
                eventName,
                step: step,
                invariantIds: scenario.remoteHostSwitchInvariantIDs,
                payload: payload
            )
        } catch {
            codexPillSealValidationLogger.error("Failed to record Seal remote-host switch event proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func feature(scenarios: [CodexPillSealScenario]) throws -> SealFeature {
        try SealFeature(
            id: scenarios.first?.featureID ?? FeatureID("accounts"),
            scenarios: try scenarios.map(makeScenario)
        )
    }

    private static func makeScenario(_ scenario: CodexPillSealScenario) throws -> SealScenario {
        if let scheduledRefreshRequestedAndCompletedID = scenario.scheduledRefreshRequestedAndCompletedID,
           let scheduledRefreshExpectation = scenario.scheduledRefreshExpectation {
            return try SealScenario(
                id: scenario.id,
                scenarioType: .happyPath,
                supportedExecutionModes: [.liveUI],
                expectations: [
                    try SealExpectation(
                        text: scheduledRefreshExpectation,
                        invariants: [
                            SealInvariantRef(
                                id: scheduledRefreshRequestedAndCompletedID,
                                requiredEvidence: [
                                    EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream)
                                ],
                                rule: scenario.scheduledRefreshRequestedAndCompletedRule
                            ),
                            SealInvariantRef(
                                id: scenario.scheduledRefreshPreservesAccountCatalogID,
                                requiredEvidence: [
                                    EvidenceRequirement(id: EvidenceID("account_before"), kind: .snapshot),
                                    EvidenceRequirement(id: EvidenceID("account_after"), kind: .snapshot)
                                ],
                                rule: scenario.scheduledRefreshPreservesAccountCatalogRule
                            ),
                            SealInvariantRef(
                                id: scenario.scheduledRefreshNoBlockingAlertID,
                                requiredEvidence: [
                                    EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                    EvidenceRequirement(id: EvidenceID("menu_after"), kind: .snapshot)
                                ],
                                rule: scenario.scheduledRefreshNoBlockingAlertRule
                            )
                        ]
                    )
                ]
            )
        }

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
                                    EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                    EvidenceRequirement(id: EvidenceID("host_validation_snapshot"), kind: .snapshot)
                                ],
                                rule: scenario.hostValidationRule
                            )
                        ]
                    )
                ]
            )
        }

        if let remoteHostSwitchID = scenario.remoteHostSwitchID,
           let remoteHostSwitchExpectation = scenario.remoteHostSwitchExpectation {
            return try SealScenario(
                id: scenario.id,
                scenarioType: .happyPath,
                supportedExecutionModes: [.liveUI],
                expectations: [
                    try SealExpectation(
                        text: remoteHostSwitchExpectation,
                        invariants: [
                            SealInvariantRef(
                                id: remoteHostSwitchID,
                                requiredEvidence: [
                                    EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream)
                                ],
                                rule: scenario.remoteHostSwitchRule
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
    private static let remoteHostSwitchHostName = "buildbox"

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
    let remoteHostSwitchID: InvariantID?
    let scheduledRefreshRequestedAndCompletedID: InvariantID?
    let presentedAndCancelledExpectation: String
    let nonMutatingExpectation: String
    let switchExpectation: String?
    let hostExpectation: String?
    let remoteHostSwitchExpectation: String?
    let scheduledRefreshExpectation: String?

    var switchInvariantIDs: [InvariantID] {
        switchChangesActiveAccountID.map { [$0] } ?? []
    }

    var hostInvariantIDs: [InvariantID] {
        hostValidationID.map { [$0] } ?? []
    }

    var remoteHostSwitchInvariantIDs: [InvariantID] {
        remoteHostSwitchID.map { [$0] } ?? []
    }

    var scheduledRefreshPreservesAccountCatalogID: InvariantID {
        InvariantID("accounts.scheduled_refresh.preserves_account_catalog")
    }

    var scheduledRefreshNoBlockingAlertID: InvariantID {
        InvariantID("accounts.scheduled_refresh.no_blocking_alert")
    }

    var scheduledRefreshInvariantIDs: [InvariantID] {
        guard let scheduledRefreshRequestedAndCompletedID else { return [] }
        return [
            scheduledRefreshRequestedAndCompletedID,
            scheduledRefreshPreservesAccountCatalogID,
            scheduledRefreshNoBlockingAlertID
        ]
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
        .all([
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
            ]),
            .snapshotEquals(
                SnapshotEqualsRule(
                    evidence: EvidenceID("host_validation_snapshot"),
                    path: "validationResult",
                    value: .string("failed")
                )
            )
        ])
    }

    var remoteHostSwitchRule: SealRule {
        .eventSequence([
            EventExpectation("menu_action_dispatched", payload: [
                "action": .string("switchAccountOnHost"),
                "hostName": .string(Self.remoteHostSwitchHostName)
            ]),
            EventExpectation("remote_host_switch_started", payload: [
                "hostName": .string(Self.remoteHostSwitchHostName)
            ]),
            EventExpectation("remote_host_active_account_changed", payload: [
                "hostName": .string(Self.remoteHostSwitchHostName)
            ]),
        ])
    }

    var scheduledRefreshRequestedAndCompletedRule: SealRule {
        .eventSequence([
            EventExpectation("scheduled_refresh_requested"),
            EventExpectation("scheduled_refresh_completed"),
        ])
    }

    var scheduledRefreshPreservesAccountCatalogRule: SealRule {
        .snapshotsEqual(
            SnapshotsEqualRule(
                before: EvidenceID("account_before"),
                after: EvidenceID("account_after"),
                paths: ["savedAccounts"]
            )
        )
    }

    var scheduledRefreshNoBlockingAlertRule: SealRule {
        .all([
            .eventExists(EventExpectation("scheduled_refresh_completed")),
            .snapshotEquals(
                SnapshotEqualsRule(
                    evidence: EvidenceID("menu_after"),
                    path: "noBlockingAlert",
                    value: .bool(true)
                )
            )
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
        hostExpectation: String? = nil,
        remoteHostSwitchID: InvariantID? = nil,
        remoteHostSwitchExpectation: String? = nil,
        scheduledRefreshRequestedAndCompletedID: InvariantID? = nil,
        scheduledRefreshExpectation: String? = nil
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
        self.remoteHostSwitchID = remoteHostSwitchID
        self.scheduledRefreshRequestedAndCompletedID = scheduledRefreshRequestedAndCompletedID
        self.presentedAndCancelledExpectation = presentedAndCancelledExpectation
        self.nonMutatingExpectation = nonMutatingExpectation
        self.switchExpectation = switchExpectation
        self.hostExpectation = hostExpectation
        self.remoteHostSwitchExpectation = remoteHostSwitchExpectation
        self.scheduledRefreshExpectation = scheduledRefreshExpectation
    }

    init?(legacyScenario: String) {
        switch legacyScenario {
        case "live-add-account-name-dialog-cancelled", "live-add-account-prompt":
            self = .addAccountNameDialogCancelled
        case "live-account-switch":
            self = .switchAccountChangesActiveAccount
        case "live-add-host-destination-validation-failed", "live-add-host-prompt":
            self = .addHostDestinationValidationFailed
        case "live-remote-host-switch":
            self = .switchAccountOnHostChangesRemoteActiveAccount
        case "live-scheduled-refresh":
            self = .scheduledRefreshPreservesAccountCatalog
        default:
            return nil
        }
    }

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

    static let switchAccountOnHostChangesRemoteActiveAccount = CodexPillSealScenario(
        featureID: FeatureID("hosts"),
        id: ScenarioID("switch-account-on-host-changes-remote-active-account"),
        menuAction: "switchAccountOnHost",
        dialogID: "remote_host_switch",
        dialogTitle: "Switch Account on Host",
        dialogStep: "remote_host_switch",
        presentedEventName: "remote_host_switch_started",
        cancelledEventName: "remote_host_switch_cancelled",
        nameDialogPresentedID: InvariantID("hosts.switch_account_on_host.started"),
        nameDialogCancelledID: InvariantID("hosts.switch_account_on_host.cancelled"),
        cancelKeepsAccountStateID: InvariantID("hosts.switch_account_on_host.cancel_keeps_remote_account_state"),
        presentedAndCancelledExpectation: "The remote-host switch workflow starts",
        nonMutatingExpectation: "Cancelling the remote-host switch workflow does not change remote account state",
        remoteHostSwitchID: InvariantID("hosts.switch_account_on_host.changes_remote_active_account"),
        remoteHostSwitchExpectation: "Switching account through a host submenu changes that host's active remote account"
    )

    static let scheduledRefreshPreservesAccountCatalog = CodexPillSealScenario(
        id: ScenarioID("scheduled-refresh-preserves-account-catalog"),
        menuAction: "scheduledRefresh",
        dialogID: "scheduled_refresh",
        dialogTitle: "Scheduled Refresh",
        dialogStep: "scheduled_refresh",
        presentedEventName: "scheduled_refresh_requested",
        cancelledEventName: "scheduled_refresh_failed",
        nameDialogPresentedID: InvariantID("accounts.scheduled_refresh.requested_and_completed"),
        nameDialogCancelledID: InvariantID("accounts.scheduled_refresh.failed"),
        cancelKeepsAccountStateID: InvariantID("accounts.scheduled_refresh.preserves_account_catalog"),
        presentedAndCancelledExpectation: "Scheduled refresh requests and completes",
        nonMutatingExpectation: "Scheduled refresh preserves the saved account catalog",
        scheduledRefreshRequestedAndCompletedID: InvariantID("accounts.scheduled_refresh.requested_and_completed"),
        scheduledRefreshExpectation: "Scheduled refresh completes without changing the saved account catalog or blocking the menubar"
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

private struct ScheduledRefreshMenuEvidence: Encodable {
    let statusMessage: String?
    let menuItemCount: Int
    let lastMenuAction: String?
    let lastConfirmationRequest: String?
    let noBlockingAlert: Bool

    init(snapshot: MenuBarValidationSnapshot) {
        self.statusMessage = snapshot.statusMessage
        self.menuItemCount = snapshot.menuItems.count
        self.lastMenuAction = snapshot.actionTrace?.lastMenuAction
        self.lastConfirmationRequest = snapshot.actionTrace?.lastConfirmationRequest
        self.noBlockingAlert = snapshot.actionTrace?.lastConfirmationRequest == nil
    }
}

private struct NameDialogSnapshot: Encodable {
    let dialogId: String
    let title: String
    let wasPresented: Bool
    let finalState: String
}

private struct HostValidationSnapshot: Encodable {
    let hostName: String
    let validationResult: String
    let message: String
}
