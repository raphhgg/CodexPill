import Foundation
import SealRecorder

enum AccountSealScenarioCatalog {
    static func feature(scenarios: [AccountSealScenario]) throws -> SealFeature {
        try SealFeature(
            id: FeatureID("accounts"),
            scenarios: try scenarios.map(makeScenario)
        )
    }

    private static func makeScenario(_ scenario: AccountSealScenario) throws -> SealScenario {
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
                                id: scenario.scheduledRefreshPreservesAccountCatalogIdentityID,
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
                                    EvidenceRequirement(id: EvidenceID("ui_after_refresh"), kind: .snapshot)
                                ],
                                rule: scenario.scheduledRefreshNoBlockingAlertRule
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
                                    EvidenceRequirement(id: EvidenceID("account_after"), kind: .snapshot),
                                    EvidenceRequirement(id: EvidenceID("post_switch_refresh"), kind: .snapshot)
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

struct AccountSealScenario {
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
    let scheduledRefreshRequestedAndCompletedID: InvariantID?
    let presentedAndCancelledExpectation: String
    let nonMutatingExpectation: String
    let switchExpectation: String?
    let scheduledRefreshExpectation: String?

    var switchInvariantIDs: [InvariantID] {
        switchChangesActiveAccountID.map { [$0] } ?? []
    }

    var scheduledRefreshPreservesAccountCatalogIdentityID: InvariantID {
        InvariantID("accounts.scheduled_refresh.preserves_account_catalog_identity")
    }

    var scheduledRefreshNoBlockingAlertID: InvariantID {
        InvariantID("accounts.scheduled_refresh.no_blocking_alert_visible")
    }

    var scheduledRefreshInvariantIDs: [InvariantID] {
        guard let scheduledRefreshRequestedAndCompletedID else { return [] }
        return [
            scheduledRefreshRequestedAndCompletedID,
            scheduledRefreshPreservesAccountCatalogIdentityID,
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
                EventExpectation("codex_relaunch_requested"),
                EventExpectation("post_switch_refresh_completed")
            ]),
            .eventExists(EventExpectation("active_account_changed")),
            .snapshotsDiffer(
                SnapshotsDifferRule(
                    before: EvidenceID("account_before"),
                    after: EvidenceID("account_after"),
                    paths: ["activeAccountId"]
                )
            ),
            .snapshotEquals(
                SnapshotEqualsRule(
                    evidence: EvidenceID("post_switch_refresh"),
                    path: "relaunchRequested",
                    value: .bool(true)
                )
            ),
            .snapshotEquals(
                SnapshotEqualsRule(
                    evidence: EvidenceID("post_switch_refresh"),
                    path: "refreshCompleted",
                    value: .bool(true)
                )
            )
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
                paths: [
                    "activeAccountId",
                    "savedAccountIds",
                    "savedAccountNames",
                    "savedAccountCount"
                ]
            )
        )
    }

    var scheduledRefreshNoBlockingAlertRule: SealRule {
        .all([
            .eventExists(EventExpectation("scheduled_refresh_completed")),
            .snapshotEquals(
                SnapshotEqualsRule(
                    evidence: EvidenceID("ui_after_refresh"),
                    path: "hasBlockingAlert",
                    value: .bool(false)
                )
            )
        ])
    }

    private init(
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
        scheduledRefreshRequestedAndCompletedID: InvariantID? = nil,
        scheduledRefreshExpectation: String? = nil
    ) {
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
        self.scheduledRefreshRequestedAndCompletedID = scheduledRefreshRequestedAndCompletedID
        self.presentedAndCancelledExpectation = presentedAndCancelledExpectation
        self.nonMutatingExpectation = nonMutatingExpectation
        self.switchExpectation = switchExpectation
        self.scheduledRefreshExpectation = scheduledRefreshExpectation
    }

    init?(legacyScenario: String) {
        switch legacyScenario {
        case "live-add-account-name-dialog-cancelled", "live-add-account-prompt":
            self = .addAccountNameDialogCancelled
        case "live-account-switch":
            self = .switchAccountChangesActiveAccount
        case "live-scheduled-refresh":
            self = .scheduledRefreshPreservesAccountCatalog
        default:
            return nil
        }
    }

    static let addAccountNameDialogCancelled = AccountSealScenario(
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

    static let switchAccountChangesActiveAccount = AccountSealScenario(
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

    static let scheduledRefreshPreservesAccountCatalog = AccountSealScenario(
        id: ScenarioID("scheduled-refresh-preserves-account-catalog"),
        menuAction: "scheduledRefresh",
        dialogID: "scheduled_refresh",
        dialogTitle: "Scheduled Refresh",
        dialogStep: "scheduled_refresh",
        presentedEventName: "scheduled_refresh_requested",
        cancelledEventName: "scheduled_refresh_failed",
        nameDialogPresentedID: InvariantID("accounts.scheduled_refresh.requested_and_completed"),
        nameDialogCancelledID: InvariantID("accounts.scheduled_refresh.failed"),
        cancelKeepsAccountStateID: InvariantID("accounts.scheduled_refresh.preserves_account_catalog_identity"),
        presentedAndCancelledExpectation: "Scheduled refresh requests and completes",
        nonMutatingExpectation: "Scheduled refresh preserves the saved account catalog",
        scheduledRefreshRequestedAndCompletedID: InvariantID("accounts.scheduled_refresh.requested_and_completed"),
        scheduledRefreshExpectation: "Scheduled refresh completes without changing the saved account catalog or blocking the menubar"
    )
}
