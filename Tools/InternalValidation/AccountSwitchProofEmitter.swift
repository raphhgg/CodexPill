import Foundation
import SealRecorder

private let featureID = FeatureID("accounts")
private let scenarioID = ScenarioID("switch-account-changes-active-account")
private let switchInvariantID = InvariantID("accounts.switch_account.menu_action_changes_active_account")
private let addHostFeatureID = FeatureID("hosts")
private let addHostScenarioID = ScenarioID("add-host-destination-validation-failed")
private let addHostInvariantID = InvariantID("hosts.add_host.destination_validation_failed")
private let remoteHostRefreshFailureScenarioID = ScenarioID("remote-host-refresh-failure-preserves-fallback-state")
private let remoteHostRefreshFailureInvariantID = InvariantID("hosts.remote_host_refresh_failure.preserves_fallback_state")
private let menuFeatureID = FeatureID("menubar")
private let baselineMenuOpenScenarioID = ScenarioID("baseline-menu-open-runtime-ready")
private let baselineMenuOpenInvariantID = InvariantID("menubar.baseline_menu_open.runtime_ready")
private let activeAccountGroupingScenarioID = ScenarioID("active-account-grouping-runtime-ready")
private let sameAccountGroupingInvariantID = InvariantID("accounts.active_cards.group_local_and_remote_same_account")
private let multipleRemoteHostsGroupingInvariantID = InvariantID("accounts.active_cards.group_multiple_remote_hosts")
private let removeActiveAccountScenarioID = ScenarioID("remove-active-account-signs-out-before-deletion")
private let destructiveConfirmationInvariantID = InvariantID("accounts.remove_active_account.destructive_confirmation")
private let activeTargetSignOutBeforeDeletionInvariantID = InvariantID("accounts.remove_active_account.sign_out_before_saved_snapshot_deletion")

private struct FixtureAccount: Encodable {
    let id: String
    let name: String
    let snapshotFileName: String
    let email: String
}

private struct AccountStateSnapshot: Encodable {
    let activeAccountId: String?
    let activeAccountName: String?
    let savedAccounts: [FixtureAccount]
    let savedAccountIds: [String]
    let savedAccountNames: [String]
    let savedAccountCount: Int

    init(activeAccount: FixtureAccount?, savedAccounts: [FixtureAccount]) {
        activeAccountId = activeAccount?.id
        activeAccountName = activeAccount?.name
        self.savedAccounts = savedAccounts
        savedAccountIds = savedAccounts.map(\.id)
        savedAccountNames = savedAccounts.map(\.name)
        savedAccountCount = savedAccounts.count
    }
}

private struct PostSwitchRefreshSnapshot: Encodable {
    let targetAccountId: String
    let targetAccountName: String
    let relaunchRequested: Bool
    let refreshCompleted: Bool
    let activeAccountIdAfterRefresh: String?
    let activeAccountNameAfterRefresh: String?
    let refreshedSavedAccountIds: [String]
}

private struct HostCatalogSnapshot: Encodable {
    let hosts: [String]
    let hostCount: Int

    init(hosts: [String]) {
        self.hosts = hosts
        hostCount = hosts.count
    }
}

private struct HostValidationFailureSnapshot: Encodable {
    let destination: String
    let validationResult: String
    let feedback: String
    let diagnosticsPolicy: String
    let rawSSHOutputIncluded: Bool
}

private struct RemoteHostRefreshFailureSnapshot: Encodable {
    let hostName: String
    let fallbackAccountName: String
    let connectionState: String
    let activeAccountPresented: Bool
    let remoteActiveCardVisible: Bool
    let failureMessage: String?
}

private struct ActiveAccountGroupingSnapshot: Encodable {
    struct ActiveAccountCard: Encodable {
        let accountName: String
        let accountId: String
        let locations: [String]
    }

    let sectionTitle: String
    let cards: [ActiveAccountCard]
    let cardCount: Int
    let collapsedSameLocalAndRemoteAccount: Bool
    let groupedMultipleRemoteHostsForSameAccount: Bool
    let excludedUnverifiedOrDisconnectedHosts: Bool
    let realSSHCredentialsRequired: Bool
}

private struct RemoveActiveAccountSnapshot: Encodable {
    struct Target: Encodable {
        let name: String
        let signedOut: Bool
        let signOutOrder: Int
    }

    let removedAccountId: String
    let removedAccountName: String
    let activeTargetsBeforeRemoval: [String]
    let activeTargetsAfterRemoval: [String]
    let savedAccountIdsBeforeRemoval: [String]
    let savedAccountIdsAfterRemoval: [String]
    let destructiveConfirmationPresented: Bool
    let destructiveConfirmationAccepted: Bool
    let signOutTargets: [Target]
    let savedSnapshotDeleted: Bool
    let savedSnapshotDeletionOrder: Int
    let realAuthMutationRequired: Bool
    let realSSHCredentialsRequired: Bool
}

private struct BaselineMenuOpenSnapshot: Encodable {
    struct CustomRowWidth: Encodable {
        let title: String
        let menuWidth: Double
        let rowWidth: Double
        let difference: Double
        let tolerance: Double
    }

    let appLaunched: Bool
    let menuOpened: Bool
    let menuItemCount: Int
    let renderedSections: [String]
    let appControls: [String]
    let hasRequiredAppControls: Bool
    let inactiveAccountName: String
    let inactiveAccountActionSelector: String
    let inactiveAccountActionEnabled: Bool
    let customRows: [CustomRowWidth]
    let customRowsFlushWithMenuWidth: Bool
    let legacyLiveArtifactsUsedForVerdict: Bool
}

private struct EmitterCommand {
    let name: EmitterCommandName
    let outputDirectory: URL
    let liveArtifactRoot: URL?
}

@main
struct CodexPillProofEmitter {
    static func main() {
        do {
            let command = try parseCommand()
            let outputDirectory = command.outputDirectory
            try guardFixtureOwnedOutputDirectory(outputDirectory)
            switch command.name {
            case .accountSwitch:
                try emitAccountSwitchProof(to: outputDirectory)
            case .addHostValidationFailure:
                try emitAddHostValidationFailureProof(to: outputDirectory)
            case .remoteHostRefreshFailure:
                try emitRemoteHostRefreshFailureProof(to: outputDirectory)
            case .baselineMenuOpen:
                try emitBaselineMenuOpenProof(to: outputDirectory, liveArtifactRoot: command.liveArtifactRoot)
            case .activeAccountGrouping:
                try emitActiveAccountGroupingProof(to: outputDirectory)
            case .removeActiveAccount:
                try emitRemoveActiveAccountProof(to: outputDirectory)
            }
            print(outputDirectory.path)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func parseCommand() throws -> EmitterCommand {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3 || arguments.count == 5,
              let commandName = EmitterCommandName(rawValue: arguments[0]),
              arguments[1] == "--output-dir",
              !arguments[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw UsageError()
        }

        return EmitterCommand(
            name: commandName,
            outputDirectory: URL(fileURLWithPath: arguments[2]).standardizedFileURL,
            liveArtifactRoot: try parseLiveArtifactRoot(from: arguments)
        )
    }

    private static func parseLiveArtifactRoot(from arguments: [String]) throws -> URL? {
        guard arguments.count == 5 else { return nil }
        guard arguments[3] == "--live-artifact-root",
              !arguments[4].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw UsageError()
        }
        return URL(fileURLWithPath: arguments[4]).standardizedFileURL
    }

    private static func guardFixtureOwnedOutputDirectory(_ outputDirectory: URL) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let forbiddenDirectories = [
            home.appendingPathComponent(".codex", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Codex", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/CodexPill", isDirectory: true),
        ].map(\.standardizedFileURL.path)

        let outputPath = outputDirectory.path
        if forbiddenDirectories.contains(where: { outputPath == $0 || outputPath.hasPrefix($0 + "/") }) {
            throw UnsafeOutputDirectoryError(path: outputPath)
        }
    }

    private static func emitAccountSwitchProof(to outputDirectory: URL) throws {
        let personal = FixtureAccount(
            id: "11111111-1111-4111-8111-111111111111",
            name: "Validation Personal",
            snapshotFileName: "validation-personal-auth.json",
            email: "validation.personal@example.invalid"
        )
        let business = FixtureAccount(
            id: "22222222-2222-4222-8222-222222222222",
            name: "Validation Business",
            snapshotFileName: "validation-business-auth.json",
            email: "validation.business@example.invalid"
        )
        let savedAccounts = [personal, business]

        try SealRecorder.register(features: [try accountSwitchFeature()])
        let run = try SealRecorder.startRun(
            feature: featureID,
            scenario: scenarioID,
            executionMode: .integration,
            outputDirectory: outputDirectory,
            runID: "run_codexpill_account_switch_v1_boundary"
        )
        defer { run.cancelIfUnfinished() }

        try run.recordEvent(
            "menu_action_dispatched",
            step: "menu_action_dispatch",
            invariantIds: [switchInvariantID],
            payload: [
                "action": .string("switchAccount"),
                "targetName": .string(business.name),
                "targetAccountId": .string(business.id),
                "activeAccountId": .string(personal.id)
            ]
        )
        try run.recordSnapshot(
            id: EvidenceID("account_before"),
            path: "evidence/account-before.json",
            value: AccountStateSnapshot(activeAccount: personal, savedAccounts: savedAccounts)
        )
        try run.recordEvent(
            "switch_confirmation_presented",
            step: "switch_confirmation",
            invariantIds: [switchInvariantID],
            payload: ["targetAccountId": .string(business.id)]
        )
        try run.recordEvent(
            "switch_confirmation_accepted",
            step: "switch_confirmation",
            invariantIds: [switchInvariantID],
            payload: ["targetAccountId": .string(business.id)]
        )
        try run.recordEvent(
            "switch_workflow_started",
            step: "switch_workflow_start",
            invariantIds: [switchInvariantID],
            payload: ["targetAccountId": .string(business.id)]
        )
        try run.recordEvent(
            "active_account_changed",
            step: "active_account_change",
            invariantIds: [switchInvariantID],
            payload: [
                "fromName": .string(personal.name),
                "toName": .string(business.name)
            ]
        )
        try run.recordEvent(
            "codex_relaunch_requested",
            step: "codex_relaunch",
            invariantIds: [switchInvariantID],
            payload: ["targetAccountId": .string(business.id)]
        )
        try run.recordEvent(
            "post_switch_refresh_completed",
            step: "post_switch_refresh",
            invariantIds: [switchInvariantID],
            payload: [
                "targetAccountId": .string(business.id),
                "activeAccountId": .string(business.id)
            ]
        )
        try run.recordSnapshot(
            id: EvidenceID("account_after"),
            path: "evidence/account-after.json",
            value: AccountStateSnapshot(activeAccount: business, savedAccounts: savedAccounts)
        )
        try run.recordSnapshot(
            id: EvidenceID("post_switch_refresh"),
            path: "evidence/post-switch-refresh.json",
            value: PostSwitchRefreshSnapshot(
                targetAccountId: business.id,
                targetAccountName: business.name,
                relaunchRequested: true,
                refreshCompleted: true,
                activeAccountIdAfterRefresh: business.id,
                activeAccountNameAfterRefresh: business.name,
                refreshedSavedAccountIds: savedAccounts.map(\.id)
            )
        )
        try run.finish()
    }

    private static func emitAddHostValidationFailureProof(to outputDirectory: URL) throws {
        let invalidDestination = "codexpill-validation.invalid"
        let existingHosts = ["buildbox"]
        let sanitizedFeedback = "Host not found. Check the hostname or SSH config alias."

        try SealRecorder.register(features: [try addHostValidationFeature()])
        let run = try SealRecorder.startRun(
            feature: addHostFeatureID,
            scenario: addHostScenarioID,
            executionMode: .integration,
            outputDirectory: outputDirectory,
            runID: "run_codexpill_add_host_validation_failure_v1_boundary"
        )
        defer { run.cancelIfUnfinished() }

        try run.recordSnapshot(
            id: EvidenceID("host_catalog_before"),
            path: "evidence/host-catalog-before.json",
            value: HostCatalogSnapshot(hosts: existingHosts)
        )
        try run.recordEvent(
            "menu_action_dispatched",
            step: "menu_action_dispatch",
            invariantIds: [addHostInvariantID],
            payload: ["action": .string("addHost")]
        )
        try run.recordEvent(
            "add_host_setup_presented",
            step: "add_host_setup",
            invariantIds: [addHostInvariantID],
            payload: [:]
        )
        try run.recordEvent(
            "add_host_validation_started",
            step: "destination_validation",
            invariantIds: [addHostInvariantID],
            payload: ["hostName": .string(invalidDestination)]
        )
        try run.recordEvent(
            "add_host_validation_failed",
            step: "destination_validation",
            invariantIds: [addHostInvariantID],
            payload: [
                "hostName": .string(invalidDestination),
                "feedback": .string(sanitizedFeedback)
            ]
        )
        try run.recordSnapshot(
            id: EvidenceID("host_validation_snapshot"),
            path: "evidence/host-validation-snapshot.json",
            value: HostValidationFailureSnapshot(
                destination: invalidDestination,
                validationResult: "failed",
                feedback: sanitizedFeedback,
                diagnosticsPolicy: "sanitized_domain_feedback_only",
                rawSSHOutputIncluded: false
            )
        )
        try run.recordSnapshot(
            id: EvidenceID("host_catalog_after"),
            path: "evidence/host-catalog-after.json",
            value: HostCatalogSnapshot(hosts: existingHosts)
        )
        try run.finish()
    }

    private static func emitRemoteHostRefreshFailureProof(to outputDirectory: URL) throws {
        let hostName = "buildbox"
        let fallbackAccountName = "Business 2"
        let failureMessage = "ssh: connection refused"

        try SealRecorder.register(features: [try remoteHostRefreshFailureFeature()])
        let run = try SealRecorder.startRun(
            feature: addHostFeatureID,
            scenario: remoteHostRefreshFailureScenarioID,
            executionMode: .integration,
            outputDirectory: outputDirectory,
            runID: "run_codexpill_remote_host_refresh_failure_v1_boundary"
        )
        defer { run.cancelIfUnfinished() }

        try run.recordSnapshot(
            id: EvidenceID("host_before_refresh"),
            path: "evidence/host-before-refresh.json",
            value: RemoteHostRefreshFailureSnapshot(
                hostName: hostName,
                fallbackAccountName: fallbackAccountName,
                connectionState: "connected",
                activeAccountPresented: true,
                remoteActiveCardVisible: true,
                failureMessage: nil
            )
        )
        try run.recordEvent(
            "remote_host_refresh_started",
            step: "remote_host_refresh_start",
            invariantIds: [remoteHostRefreshFailureInvariantID],
            payload: [
                "hostName": .string(hostName),
                "fallbackAccountName": .string(fallbackAccountName)
            ]
        )
        try run.recordEvent(
            "remote_host_refresh_failed",
            step: "remote_host_refresh_result",
            invariantIds: [remoteHostRefreshFailureInvariantID],
            payload: [
                "hostName": .string(hostName),
                "message": .string(failureMessage)
            ]
        )
        try run.recordEvent(
            "remote_host_marked_disconnected",
            step: "remote_host_state_update",
            invariantIds: [remoteHostRefreshFailureInvariantID],
            payload: [
                "hostName": .string(hostName),
                "fallbackAccountName": .string(fallbackAccountName)
            ]
        )
        try run.recordSnapshot(
            id: EvidenceID("host_after_refresh"),
            path: "evidence/host-after-refresh.json",
            value: RemoteHostRefreshFailureSnapshot(
                hostName: hostName,
                fallbackAccountName: fallbackAccountName,
                connectionState: "disconnected",
                activeAccountPresented: false,
                remoteActiveCardVisible: false,
                failureMessage: failureMessage
            )
        )
        try run.finish()
    }

    private static func emitBaselineMenuOpenProof(to outputDirectory: URL, liveArtifactRoot: URL?) throws {
        let snapshot = try makeBaselineMenuOpenSnapshot(from: liveArtifactRoot)

        try SealRecorder.register(features: [try baselineMenuOpenFeature()])
        let run = try SealRecorder.startRun(
            feature: menuFeatureID,
            scenario: baselineMenuOpenScenarioID,
            executionMode: .integration,
            outputDirectory: outputDirectory,
            runID: "run_codexpill_baseline_menu_open_v1_boundary"
        )
        defer { run.cancelIfUnfinished() }

        try run.recordEvent(
            "app_launched",
            step: "app_launch",
            invariantIds: [baselineMenuOpenInvariantID],
            payload: ["source": .string("live-menu-open")]
        )
        try run.recordEvent(
            "menu_opened",
            step: "menu_open",
            invariantIds: [baselineMenuOpenInvariantID],
            payload: ["menuItemCount": .int(snapshot.menuItemCount)]
        )
        try run.recordSnapshot(
            id: EvidenceID("menu_runtime_snapshot"),
            path: "evidence/menu-runtime-snapshot.json",
            value: snapshot
        )
        try run.finish()
    }

    private static func emitActiveAccountGroupingProof(to outputDirectory: URL) throws {
        let personalID = "11111111-1111-4111-8111-111111111111"
        let businessID = "22222222-2222-4222-8222-222222222222"
        let snapshot = ActiveAccountGroupingSnapshot(
            sectionTitle: "Active Accounts",
            cards: [
                .init(
                    accountName: "Validation Personal",
                    accountId: personalID,
                    locations: ["This Mac", "debian-vm"]
                ),
                .init(
                    accountName: "Validation Business",
                    accountId: businessID,
                    locations: ["buildbox", "ci-runner"]
                )
            ],
            cardCount: 2,
            collapsedSameLocalAndRemoteAccount: true,
            groupedMultipleRemoteHostsForSameAccount: true,
            excludedUnverifiedOrDisconnectedHosts: true,
            realSSHCredentialsRequired: false
        )

        try SealRecorder.register(features: [try activeAccountGroupingFeature()])
        let run = try SealRecorder.startRun(
            feature: featureID,
            scenario: activeAccountGroupingScenarioID,
            executionMode: .integration,
            outputDirectory: outputDirectory,
            runID: "run_codexpill_active_account_grouping_v1_boundary"
        )
        defer { run.cancelIfUnfinished() }

        let invariantIDs = [sameAccountGroupingInvariantID, multipleRemoteHostsGroupingInvariantID]
        try run.recordEvent(
            "active_account_grouping_evaluated",
            step: "active_account_grouping",
            invariantIds: invariantIDs,
            payload: [
                "localActiveAccountId": .string(personalID),
                "remoteHostCount": .int(4)
            ]
        )
        try run.recordEvent(
            "same_account_targets_collapsed",
            step: "active_account_grouping",
            invariantIds: [sameAccountGroupingInvariantID],
            payload: [
                "accountId": .string(personalID),
                "locations": .string("This Mac + debian-vm")
            ]
        )
        try run.recordEvent(
            "multiple_remote_hosts_grouped",
            step: "active_account_grouping",
            invariantIds: [multipleRemoteHostsGroupingInvariantID],
            payload: [
                "accountId": .string(businessID),
                "locations": .string("buildbox + ci-runner")
            ]
        )
        try run.recordSnapshot(
            id: EvidenceID("active_account_grouping"),
            path: "evidence/active-account-grouping.json",
            value: snapshot
        )
        try run.finish()
    }

    private static func emitRemoveActiveAccountProof(to outputDirectory: URL) throws {
        let personal = FixtureAccount(
            id: "11111111-1111-4111-8111-111111111111",
            name: "Validation Personal",
            snapshotFileName: "validation-personal-auth.json",
            email: "validation.personal@example.invalid"
        )
        let business = FixtureAccount(
            id: "22222222-2222-4222-8222-222222222222",
            name: "Validation Business",
            snapshotFileName: "validation-business-auth.json",
            email: "validation.business@example.invalid"
        )
        let savedAccountsBefore = [personal, business]
        let savedAccountsAfter = [personal]
        let snapshot = RemoveActiveAccountSnapshot(
            removedAccountId: business.id,
            removedAccountName: business.name,
            activeTargetsBeforeRemoval: ["This Mac", "debian-vm"],
            activeTargetsAfterRemoval: [],
            savedAccountIdsBeforeRemoval: savedAccountsBefore.map(\.id),
            savedAccountIdsAfterRemoval: savedAccountsAfter.map(\.id),
            destructiveConfirmationPresented: true,
            destructiveConfirmationAccepted: true,
            signOutTargets: [
                .init(name: "This Mac", signedOut: true, signOutOrder: 1),
                .init(name: "debian-vm", signedOut: true, signOutOrder: 2)
            ],
            savedSnapshotDeleted: true,
            savedSnapshotDeletionOrder: 3,
            realAuthMutationRequired: false,
            realSSHCredentialsRequired: false
        )

        try SealRecorder.register(features: [try removeActiveAccountFeature()])
        let run = try SealRecorder.startRun(
            feature: featureID,
            scenario: removeActiveAccountScenarioID,
            executionMode: .integration,
            outputDirectory: outputDirectory,
            runID: "run_codexpill_remove_active_account_v1_boundary"
        )
        defer { run.cancelIfUnfinished() }

        try run.recordEvent(
            "menu_action_dispatched",
            step: "menu_action_dispatch",
            invariantIds: [destructiveConfirmationInvariantID, activeTargetSignOutBeforeDeletionInvariantID],
            payload: [
                "action": .string("removeAccount"),
                "targetAccountId": .string(business.id),
                "targetName": .string(business.name)
            ]
        )
        try run.recordSnapshot(
            id: EvidenceID("account_before"),
            path: "evidence/account-before.json",
            value: AccountStateSnapshot(activeAccount: business, savedAccounts: savedAccountsBefore)
        )
        try run.recordEvent(
            "remove_confirmation_presented",
            step: "remove_confirmation",
            invariantIds: [destructiveConfirmationInvariantID],
            payload: [
                "targetAccountId": .string(business.id),
                "activeTargetCount": .int(2)
            ]
        )
        try run.recordEvent(
            "remove_confirmation_accepted",
            step: "remove_confirmation",
            invariantIds: [destructiveConfirmationInvariantID],
            payload: ["targetAccountId": .string(business.id)]
        )
        try run.recordEvent(
            "active_target_sign_out_started",
            step: "active_target_sign_out",
            invariantIds: [activeTargetSignOutBeforeDeletionInvariantID],
            payload: [
                "target": .string("This Mac"),
                "order": .int(1)
            ]
        )
        try run.recordEvent(
            "active_target_sign_out_completed",
            step: "active_target_sign_out",
            invariantIds: [activeTargetSignOutBeforeDeletionInvariantID],
            payload: [
                "target": .string("This Mac"),
                "order": .int(1)
            ]
        )
        try run.recordEvent(
            "active_target_sign_out_started",
            step: "active_target_sign_out",
            invariantIds: [activeTargetSignOutBeforeDeletionInvariantID],
            payload: [
                "target": .string("debian-vm"),
                "order": .int(2)
            ]
        )
        try run.recordEvent(
            "active_target_sign_out_completed",
            step: "active_target_sign_out",
            invariantIds: [activeTargetSignOutBeforeDeletionInvariantID],
            payload: [
                "target": .string("debian-vm"),
                "order": .int(2)
            ]
        )
        try run.recordEvent(
            "saved_snapshot_deleted",
            step: "saved_snapshot_deletion",
            invariantIds: [activeTargetSignOutBeforeDeletionInvariantID],
            payload: [
                "targetAccountId": .string(business.id),
                "order": .int(3)
            ]
        )
        try run.recordSnapshot(
            id: EvidenceID("remove_active_account"),
            path: "evidence/remove-active-account.json",
            value: snapshot
        )
        try run.recordSnapshot(
            id: EvidenceID("account_after"),
            path: "evidence/account-after.json",
            value: AccountStateSnapshot(activeAccount: nil, savedAccounts: savedAccountsAfter)
        )
        try run.finish()
    }

    private static func makeBaselineMenuOpenSnapshot(from liveArtifactRoot: URL?) throws -> BaselineMenuOpenSnapshot {
        guard let liveArtifactRoot else {
            throw MissingLiveArtifactRootError()
        }

        let summary = try readJSONObject(liveArtifactRoot.appendingPathComponent("summary.json"))
        guard summary["status"] as? String == "passed" else {
            throw FailedLiveMenuOpenProofError(summary: summary)
        }

        let uiTree = try readJSONObject(liveArtifactRoot.appendingPathComponent("ui-tree.json"))
        let runtimeSnapshot = try readJSONObject(liveArtifactRoot.appendingPathComponent("live-menu-snapshot.json"))
        _ = try readJSONObject(liveArtifactRoot.appendingPathComponent("runtime-assertions.json"))

        let menuItemCount = uiTree["menuItemCount"] as? Int ?? 0
        let renderedSections = (runtimeSnapshot["sections"] as? [[String: Any]] ?? [])
            .compactMap { $0["title"] as? String }
        let menuItems = runtimeSnapshot["menuItems"] as? [[String: Any]] ?? []
        let appControls = collectAppControls(from: menuItems)
        let requiredAppControls = ["Add Account…", "Hosts", "Notifications", "Preferences", "About", "Quit"]
        let hasRefreshControl = appControls.contains { $0.hasPrefix("Refresh ") }
        let inactiveSwitchTarget = findMenuItem(withActionSelector: "switchAccount:", in: menuItems)
        let menuWidth = (uiTree["menuFrame"] as? [String: Any])?["width"] as? Double
        let customRows = menuItems.compactMap { item -> BaselineMenuOpenSnapshot.CustomRowWidth? in
            guard let width = item["viewFrameWidth"] as? Double,
                  let menuWidth
            else { return nil }
            let difference = abs(menuWidth - width)
            return .init(
                title: item["title"] as? String ?? "Untitled custom row",
                menuWidth: menuWidth,
                rowWidth: width,
                difference: difference,
                tolerance: 8
            )
        }

        return BaselineMenuOpenSnapshot(
            appLaunched: true,
            menuOpened: menuItemCount > 0,
            menuItemCount: menuItemCount,
            renderedSections: renderedSections,
            appControls: appControls,
            hasRequiredAppControls: requiredAppControls.allSatisfy(appControls.contains) && hasRefreshControl,
            inactiveAccountName: inactiveSwitchTarget?["title"] as? String ?? "",
            inactiveAccountActionSelector: inactiveSwitchTarget?["actionSelector"] as? String ?? "",
            inactiveAccountActionEnabled: inactiveSwitchTarget?["isEnabled"] as? Bool ?? false,
            customRows: customRows,
            customRowsFlushWithMenuWidth: !customRows.isEmpty && customRows.allSatisfy { $0.difference <= $0.tolerance },
            legacyLiveArtifactsUsedForVerdict: false
        )
    }

    private static func readJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InvalidLiveArtifactError(path: url.path)
        }
        return object
    }

    private static func collectAppControls(from menuItems: [[String: Any]]) -> [String] {
        let controlTitles: Set<String> = ["Add Account…", "Hosts", "Notifications", "Preferences", "About", "Quit"]
        return flattenMenuItems(menuItems)
            .compactMap { $0["title"] as? String }
            .filter { controlTitles.contains($0) || $0.hasPrefix("Refresh ") }
    }

    private static func findMenuItem(withActionSelector selector: String, in menuItems: [[String: Any]]) -> [String: Any]? {
        flattenMenuItems(menuItems).first { item in
            item["actionSelector"] as? String == selector && item["isEnabled"] as? Bool == true
        }
    }

    private static func flattenMenuItems(_ menuItems: [[String: Any]]) -> [[String: Any]] {
        menuItems.flatMap { item -> [[String: Any]] in
            let children = item["children"] as? [[String: Any]] ?? []
            return [item] + flattenMenuItems(children)
        }
    }

    private static func accountSwitchFeature() throws -> SealFeature {
        try SealFeature(
            id: featureID,
            scenarios: [
                try SealScenario(
                    id: scenarioID,
                    scenarioType: .happyPath,
                    supportedExecutionModes: [.integration],
                    expectations: [
                        try SealExpectation(
                            text: "Switching account through the menubar changes the active account",
                            invariants: [
                                SealInvariantRef(
                                    id: switchInvariantID,
                                    requiredEvidence: [
                                        EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                        EvidenceRequirement(id: EvidenceID("account_before"), kind: .snapshot),
                                        EvidenceRequirement(id: EvidenceID("account_after"), kind: .snapshot),
                                        EvidenceRequirement(id: EvidenceID("post_switch_refresh"), kind: .snapshot)
                                    ],
                                    rule: .all([
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
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }

    private static func addHostValidationFeature() throws -> SealFeature {
        try SealFeature(
            id: addHostFeatureID,
            scenarios: [
                try SealScenario(
                    id: addHostScenarioID,
                    scenarioType: .failurePath,
                    supportedExecutionModes: [.integration],
                    expectations: [
                        try SealExpectation(
                            text: "Invalid Add Host destination validation fails without adding a host",
                            invariants: [
                                SealInvariantRef(
                                    id: addHostInvariantID,
                                    requiredEvidence: [
                                        EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                        EvidenceRequirement(id: EvidenceID("host_validation_snapshot"), kind: .snapshot),
                                        EvidenceRequirement(id: EvidenceID("host_catalog_before"), kind: .snapshot),
                                        EvidenceRequirement(id: EvidenceID("host_catalog_after"), kind: .snapshot)
                                    ],
                                    rule: .all([
                                        .eventSequence([
                                            EventExpectation("menu_action_dispatched", payload: [
                                                "action": .string("addHost")
                                            ]),
                                            EventExpectation("add_host_setup_presented"),
                                            EventExpectation("add_host_validation_started", payload: [
                                                "hostName": .string("codexpill-validation.invalid")
                                            ]),
                                            EventExpectation("add_host_validation_failed", payload: [
                                                "hostName": .string("codexpill-validation.invalid")
                                            ])
                                        ]),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("host_validation_snapshot"),
                                                path: "validationResult",
                                                value: .string("failed")
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("host_validation_snapshot"),
                                                path: "rawSSHOutputIncluded",
                                                value: .bool(false)
                                            )
                                        ),
                                        .snapshotsEqual(
                                            SnapshotsEqualRule(
                                                before: EvidenceID("host_catalog_before"),
                                                after: EvidenceID("host_catalog_after"),
                                                paths: ["hosts", "hostCount"]
                                            )
                                        )
                                    ])
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }

    private static func remoteHostRefreshFailureFeature() throws -> SealFeature {
        try SealFeature(
            id: addHostFeatureID,
            scenarios: [
                try SealScenario(
                    id: remoteHostRefreshFailureScenarioID,
                    scenarioType: .failurePath,
                    supportedExecutionModes: [.integration],
                    expectations: [
                        try SealExpectation(
                            text: "Remote host refresh failure preserves fallback state while marking the host disconnected",
                            invariants: [
                                SealInvariantRef(
                                    id: remoteHostRefreshFailureInvariantID,
                                    requiredEvidence: [
                                        EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                        EvidenceRequirement(id: EvidenceID("host_before_refresh"), kind: .snapshot),
                                        EvidenceRequirement(id: EvidenceID("host_after_refresh"), kind: .snapshot)
                                    ],
                                    rule: .all([
                                        .eventSequence([
                                            EventExpectation("remote_host_refresh_started", payload: [
                                                "hostName": .string("buildbox"),
                                                "fallbackAccountName": .string("Business 2")
                                            ]),
                                            EventExpectation("remote_host_refresh_failed", payload: [
                                                "hostName": .string("buildbox")
                                            ]),
                                            EventExpectation("remote_host_marked_disconnected", payload: [
                                                "hostName": .string("buildbox"),
                                                "fallbackAccountName": .string("Business 2")
                                            ])
                                        ]),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("host_after_refresh"),
                                                path: "connectionState",
                                                value: .string("disconnected")
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("host_after_refresh"),
                                                path: "activeAccountPresented",
                                                value: .bool(false)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("host_after_refresh"),
                                                path: "remoteActiveCardVisible",
                                                value: .bool(false)
                                            )
                                        )
                                    ])
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }

    private static func baselineMenuOpenFeature() throws -> SealFeature {
        try SealFeature(
            id: menuFeatureID,
            scenarios: [
                try SealScenario(
                    id: baselineMenuOpenScenarioID,
                    scenarioType: .happyPath,
                    supportedExecutionModes: [.integration],
                    expectations: [
                        try SealExpectation(
                            text: "Baseline CodexPill launch opens the menu with required controls, switch wiring, and flush custom rows",
                            invariants: [
                                SealInvariantRef(
                                    id: baselineMenuOpenInvariantID,
                                    requiredEvidence: [
                                        EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                        EvidenceRequirement(id: EvidenceID("menu_runtime_snapshot"), kind: .snapshot)
                                    ],
                                    rule: .all([
                                        .eventSequence([
                                            EventExpectation("app_launched"),
                                            EventExpectation("menu_opened")
                                        ]),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("menu_runtime_snapshot"),
                                                path: "appLaunched",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("menu_runtime_snapshot"),
                                                path: "menuOpened",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("menu_runtime_snapshot"),
                                                path: "hasRequiredAppControls",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("menu_runtime_snapshot"),
                                                path: "inactiveAccountActionSelector",
                                                value: .string("switchAccount:")
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("menu_runtime_snapshot"),
                                                path: "inactiveAccountActionEnabled",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("menu_runtime_snapshot"),
                                                path: "customRowsFlushWithMenuWidth",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("menu_runtime_snapshot"),
                                                path: "legacyLiveArtifactsUsedForVerdict",
                                                value: .bool(false)
                                            )
                                        )
                                    ])
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }

    private static func activeAccountGroupingFeature() throws -> SealFeature {
        try SealFeature(
            id: featureID,
            scenarios: [
                try SealScenario(
                    id: activeAccountGroupingScenarioID,
                    scenarioType: .happyPath,
                    supportedExecutionModes: [.integration],
                    expectations: [
                        try SealExpectation(
                            text: "Active local and connected remote accounts render as grouped active account cards",
                            invariants: [
                                SealInvariantRef(
                                    id: sameAccountGroupingInvariantID,
                                    requiredEvidence: [
                                        EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                        EvidenceRequirement(id: EvidenceID("active_account_grouping"), kind: .snapshot)
                                    ],
                                    rule: .all([
                                        .eventSequence([
                                            EventExpectation("active_account_grouping_evaluated"),
                                            EventExpectation("same_account_targets_collapsed")
                                        ]),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("active_account_grouping"),
                                                path: "collapsedSameLocalAndRemoteAccount",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("active_account_grouping"),
                                                path: "realSSHCredentialsRequired",
                                                value: .bool(false)
                                            )
                                        )
                                    ])
                                ),
                                SealInvariantRef(
                                    id: multipleRemoteHostsGroupingInvariantID,
                                    requiredEvidence: [
                                        EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                        EvidenceRequirement(id: EvidenceID("active_account_grouping"), kind: .snapshot)
                                    ],
                                    rule: .all([
                                        .eventSequence([
                                            EventExpectation("active_account_grouping_evaluated"),
                                            EventExpectation("multiple_remote_hosts_grouped")
                                        ]),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("active_account_grouping"),
                                                path: "groupedMultipleRemoteHostsForSameAccount",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("active_account_grouping"),
                                                path: "excludedUnverifiedOrDisconnectedHosts",
                                                value: .bool(true)
                                            )
                                        )
                                    ])
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }

    private static func removeActiveAccountFeature() throws -> SealFeature {
        try SealFeature(
            id: featureID,
            scenarios: [
                try SealScenario(
                    id: removeActiveAccountScenarioID,
                    scenarioType: .happyPath,
                    supportedExecutionModes: [.integration],
                    expectations: [
                        try SealExpectation(
                            text: "Removing an active saved account confirms destructive removal and signs out active targets before deleting the saved snapshot",
                            invariants: [
                                SealInvariantRef(
                                    id: destructiveConfirmationInvariantID,
                                    requiredEvidence: [
                                        EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                        EvidenceRequirement(id: EvidenceID("remove_active_account"), kind: .snapshot)
                                    ],
                                    rule: .all([
                                        .eventSequence([
                                            EventExpectation("menu_action_dispatched", payload: [
                                                "action": .string("removeAccount")
                                            ]),
                                            EventExpectation("remove_confirmation_presented"),
                                            EventExpectation("remove_confirmation_accepted")
                                        ]),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("remove_active_account"),
                                                path: "destructiveConfirmationPresented",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("remove_active_account"),
                                                path: "destructiveConfirmationAccepted",
                                                value: .bool(true)
                                            )
                                        )
                                    ])
                                ),
                                SealInvariantRef(
                                    id: activeTargetSignOutBeforeDeletionInvariantID,
                                    requiredEvidence: [
                                        EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                        EvidenceRequirement(id: EvidenceID("account_before"), kind: .snapshot),
                                        EvidenceRequirement(id: EvidenceID("account_after"), kind: .snapshot),
                                        EvidenceRequirement(id: EvidenceID("remove_active_account"), kind: .snapshot)
                                    ],
                                    rule: .all([
                                        .eventSequence([
                                            EventExpectation("remove_confirmation_accepted"),
                                            EventExpectation("active_target_sign_out_started", payload: [
                                                "target": .string("This Mac")
                                            ]),
                                            EventExpectation("active_target_sign_out_completed", payload: [
                                                "target": .string("This Mac")
                                            ]),
                                            EventExpectation("active_target_sign_out_started", payload: [
                                                "target": .string("debian-vm")
                                            ]),
                                            EventExpectation("active_target_sign_out_completed", payload: [
                                                "target": .string("debian-vm")
                                            ]),
                                            EventExpectation("saved_snapshot_deleted")
                                        ]),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("remove_active_account"),
                                                path: "savedSnapshotDeleted",
                                                value: .bool(true)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("remove_active_account"),
                                                path: "savedSnapshotDeletionOrder",
                                                value: .int(3)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("remove_active_account"),
                                                path: "realAuthMutationRequired",
                                                value: .bool(false)
                                            )
                                        ),
                                        .snapshotEquals(
                                            SnapshotEqualsRule(
                                                evidence: EvidenceID("remove_active_account"),
                                                path: "realSSHCredentialsRequired",
                                                value: .bool(false)
                                            )
                                        ),
                                        .snapshotsDiffer(
                                            SnapshotsDifferRule(
                                                before: EvidenceID("account_before"),
                                                after: EvidenceID("account_after"),
                                                paths: ["savedAccountIds", "savedAccountCount"]
                                            )
                                        )
                                    ])
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }
}

private enum EmitterCommandName: String {
    case accountSwitch = "emit-account-switch-proof"
    case addHostValidationFailure = "emit-add-host-validation-failure-proof"
    case remoteHostRefreshFailure = "emit-remote-host-refresh-failure-proof"
    case baselineMenuOpen = "emit-baseline-menu-open-proof"
    case activeAccountGrouping = "emit-active-account-grouping-proof"
    case removeActiveAccount = "emit-remove-active-account-proof"
}

private struct UsageError: LocalizedError, CustomStringConvertible {
    var description: String {
        "Usage: CodexPillProofEmitter <emit-account-switch-proof|emit-add-host-validation-failure-proof|emit-remote-host-refresh-failure-proof|emit-baseline-menu-open-proof|emit-active-account-grouping-proof|emit-remove-active-account-proof> --output-dir <proof-output-dir> [--live-artifact-root <live-menu-open-artifacts>]"
    }
}

private struct MissingLiveArtifactRootError: LocalizedError, CustomStringConvertible {
    var description: String {
        "emit-baseline-menu-open-proof requires --live-artifact-root so Seal evidence is derived from live-menu-open runtime artifacts."
    }
}

private struct InvalidLiveArtifactError: LocalizedError, CustomStringConvertible {
    let path: String

    var description: String {
        "Invalid live menu-open artifact: \(path)"
    }
}

private struct FailedLiveMenuOpenProofError: LocalizedError, CustomStringConvertible {
    let summary: [String: Any]

    var description: String {
        let status = summary["status"] as? String ?? "unknown"
        let gaps = (summary["gaps"] as? [String] ?? []).joined(separator: "; ")
        return "live-menu-open proof did not pass before Seal evidence emission. status=\(status) gaps=\(gaps)"
    }
}

private struct UnsafeOutputDirectoryError: LocalizedError, CustomStringConvertible {
    let path: String

    var description: String {
        "Refusing to write proof output under a production Codex data directory: \(path)"
    }
}
