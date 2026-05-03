import Foundation
import Testing

@testable import CodexPill

@MainActor
struct CodexPillSealProofRecorderTests {
    @Test
    func proofRecorderEmitsAddAccountNameDialogProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealProof-\(UUID().uuidString)", isDirectory: true)
        let now = Date()
        let account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "personal@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let proofRecorder = try #require(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "live-add-account-name-dialog-cancelled",
        ]))
        let recorder = try #require(proofRecorder.account)

        recorder.recordAddAccountMenuAction(activeAccount: account, savedAccounts: [account])
        recorder.recordAddAccountNameDialogPresented(runningCLISessions: 1)
        recorder.recordAddAccountNameDialogCancelled(activeAccount: account, savedAccounts: [account])

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "accounts")
        #expect(runMetadata?["scenario"] as? String == "add-account-name-dialog-cancelled")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
            "evidence/account-before.json",
            "evidence/name-dialog-snapshot.json",
            "evidence/account-after.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
    }

    @Test
    func proofRecorderEmitsAccountSwitchProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealProof-\(UUID().uuidString)", isDirectory: true)
        let now = Date()
        let personal = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "personal@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let business = CodexAccount(
            id: UUID(),
            name: "Business",
            snapshotFileName: "business.json",
            createdAt: now,
            updatedAt: now,
            email: "business@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let proofRecorder = try #require(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "live-account-switch",
        ]))
        let recorder = try #require(proofRecorder.account)

        recorder.recordSwitchAccountMenuAction(targetAccount: business, activeAccount: personal, savedAccounts: [personal, business])
        recorder.recordSwitchConfirmationPresented(targetAccount: business)
        recorder.recordSwitchConfirmationAccepted(targetAccount: business)
        recorder.recordSwitchWorkflowStarted(targetAccount: business)
        recorder.recordActiveAccountChanged(fromName: personal.name, toName: business.name, activeAccount: business, savedAccounts: [personal, business])

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "accounts")
        #expect(runMetadata?["scenario"] as? String == "switch-account-changes-active-account")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
            "evidence/account-before.json",
            "evidence/account-after.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        let expectations = manifest?["targetedExpectations"] as? [[String: Any]]
        let invariants = expectations?.first?["invariants"] as? [[String: Any]]
        let rule = invariants?.first?["rule"] as? [String: Any]
        let rules = rule?["rules"] as? [[String: Any]]
        let eventSequence = rules?.first { $0["type"] as? String == "event_sequence" }
        let snapshotDiff = rules?.first { $0["type"] as? String == "snapshots_differ" }

        #expect(rule?["type"] as? String == "all")
        #expect((eventSequence?["events"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == [
            "menu_action_dispatched",
            "switch_confirmation_presented",
            "switch_confirmation_accepted",
            "switch_workflow_started",
            "active_account_changed",
        ])
        #expect(snapshotDiff?["before"] as? String == "account_before")
        #expect(snapshotDiff?["after"] as? String == "account_after")
        #expect(snapshotDiff?["paths"] as? [String] == ["activeAccountId"])
    }

    @Test
    func proofRecorderEmitsAddHostDestinationValidationProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealProof-\(UUID().uuidString)", isDirectory: true)
        let proofRecorder = try #require(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "live-add-host-destination-validation-failed",
        ]))
        let recorder = try #require(proofRecorder.host)

        recorder.recordAddHostMenuAction()
        recorder.recordAddHostSetupPresented()
        recorder.recordAddHostValidationStarted(hostName: "codexpill-validation.invalid")
        recorder.recordAddHostValidationFailed(hostName: "codexpill-validation.invalid", message: "Host unavailable")

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "hosts")
        #expect(runMetadata?["scenario"] as? String == "add-host-destination-validation-failed")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
            "evidence/host-validation-snapshot.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/host-validation-snapshot.json").path))
        let expectations = manifest?["targetedExpectations"] as? [[String: Any]]
        let invariants = expectations?.first?["invariants"] as? [[String: Any]]
        let invariant = invariants?.first
        let rule = invariant?["rule"] as? [String: Any]
        let rules = rule?["rules"] as? [[String: Any]]
        let eventSequence = rules?.first { $0["type"] as? String == "event_sequence" }
        let snapshotEquals = rules?.first { $0["type"] as? String == "snapshot_equals" }

        #expect(invariant?["requiredEvidence"] as? [String] == [
            "events",
            "host_validation_snapshot",
        ])
        #expect(rule?["type"] as? String == "all")
        #expect((eventSequence?["events"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == [
            "menu_action_dispatched",
            "add_host_setup_presented",
            "add_host_validation_started",
            "add_host_validation_failed",
        ])
        #expect(snapshotEquals?["evidence"] as? String == "host_validation_snapshot")
        #expect(snapshotEquals?["path"] as? String == "validationResult")
        #expect(snapshotEquals?["value"] as? String == "failed")
    }

    @Test
    func proofRecorderEmitsRemoteHostSwitchProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealProof-\(UUID().uuidString)", isDirectory: true)
        let proofRecorder = try #require(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "live-remote-host-switch",
        ]))
        let recorder = try #require(proofRecorder.host)

        recorder.recordRemoteHostSwitchMenuAction(targetName: "Validation Local", hostName: "buildbox")
        recorder.recordRemoteHostSwitchStarted(targetName: "Validation Local", hostName: "buildbox")
        recorder.recordRemoteHostActiveAccountChanged(targetName: "Validation Local", hostName: "buildbox")

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "hosts")
        #expect(runMetadata?["scenario"] as? String == "switch-account-on-host-changes-remote-active-account")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        let expectations = manifest?["targetedExpectations"] as? [[String: Any]]
        let invariants = expectations?.first?["invariants"] as? [[String: Any]]
        let rule = invariants?.first?["rule"] as? [String: Any]
        let ruleEvents = rule?["events"] as? [[String: Any]]
        #expect(ruleEvents?.allSatisfy { event in
            let payload = event["payload"] as? [String: Any]
            return payload?["hostName"] as? String == "buildbox"
                && payload?["targetName"] == nil
        } == true)

        let eventsURL = proofDirectory.appendingPathComponent("evidence/events.jsonl")
        let events = try String(contentsOf: eventsURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(events.compactMap { $0["event"] as? String } == [
            "menu_action_dispatched",
            "remote_host_switch_started",
            "remote_host_active_account_changed",
        ])
        #expect(events.allSatisfy { event in
            let payload = event["payload"] as? [String: Any]
            return payload?["targetName"] as? String == "Validation Local"
                && payload?["hostName"] as? String == "buildbox"
        })
    }

    @Test
    func proofRecorderEmitsScheduledRefreshProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealProof-\(UUID().uuidString)", isDirectory: true)
        let now = Date()
        let account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "personal@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let proofRecorder = try #require(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "live-scheduled-refresh",
        ]))
        let recorder = try #require(proofRecorder.account)

        recorder.recordScheduledRefreshRequested(
            accountName: account.name,
            activeAccount: account,
            savedAccounts: [account]
        )
        recorder.recordScheduledRefreshResult(
            accountName: account.name,
            error: nil,
            activeAccount: account,
            savedAccounts: [account],
            uiEvidence: AccountSealScheduledRefreshUIEvidence(
                statusMessage: nil,
                menuItemCount: 0,
                lastMenuAction: nil,
                lastConfirmationRequest: nil
            )
        )

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "accounts")
        #expect(runMetadata?["scenario"] as? String == "scheduled-refresh-preserves-account-catalog")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/events.jsonl",
            "evidence/account-before.json",
            "evidence/account-after.json",
            "evidence/ui-after-refresh.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/account-before.json").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/account-after.json").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/ui-after-refresh.json").path))

        let expectations = manifest?["targetedExpectations"] as? [[String: Any]]
        let invariants = expectations?.first?["invariants"] as? [[String: Any]]
        #expect(invariants?.compactMap { $0["id"] as? String } == [
            "accounts.scheduled_refresh.requested_and_completed",
            "accounts.scheduled_refresh.preserves_account_catalog_identity",
            "accounts.scheduled_refresh.no_blocking_alert_visible",
        ])

        let eventsURL = proofDirectory.appendingPathComponent("evidence/events.jsonl")
        let events = try String(contentsOf: eventsURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(events.compactMap { $0["event"] as? String } == [
            "scheduled_refresh_requested",
            "scheduled_refresh_completed",
        ])

        let uiAfterRefreshURL = proofDirectory.appendingPathComponent("evidence/ui-after-refresh.json")
        let uiAfterRefresh = try JSONSerialization.jsonObject(with: Data(contentsOf: uiAfterRefreshURL)) as? [String: Any]
        #expect(uiAfterRefresh?["hasBlockingAlert"] as? Bool == false)
        #expect(uiAfterRefresh?["lastConfirmationRequest"] == nil || uiAfterRefresh?["lastConfirmationRequest"] is NSNull)

        let accountBeforeURL = proofDirectory.appendingPathComponent("evidence/account-before.json")
        let accountBefore = try JSONSerialization.jsonObject(with: Data(contentsOf: accountBeforeURL)) as? [String: Any]
        #expect(accountBefore?["activeAccountId"] as? String == account.id.uuidString)
        #expect(accountBefore?["savedAccountIds"] as? [String] == [account.id.uuidString])
        #expect(accountBefore?["savedAccountNames"] as? [String] == [account.name])
        #expect(accountBefore?["savedAccountCount"] as? Int == 1)

        let noBlockingAlertRule = invariants?
            .first { $0["id"] as? String == "accounts.scheduled_refresh.no_blocking_alert_visible" }?["rule"] as? [String: Any]
        let childRules = noBlockingAlertRule?["rules"] as? [[String: Any]]
        #expect(noBlockingAlertRule?["type"] as? String == "all")
        #expect(childRules?.contains { rule in
            rule["type"] as? String == "snapshot_equals"
                && rule["evidence"] as? String == "ui_after_refresh"
                && rule["path"] as? String == "hasBlockingAlert"
                && rule["value"] as? Bool == false
        } == true)
    }

    @Test
    func proofRecorderDoesNotFinishPassingScheduledRefreshProofOnFailure() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealProof-\(UUID().uuidString)", isDirectory: true)
        let now = Date()
        let account = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "personal.json",
            createdAt: now,
            updatedAt: now,
            email: "personal@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: .empty
        )
        let proofRecorder = try #require(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "live-scheduled-refresh",
        ]))
        let recorder = try #require(proofRecorder.account)

        recorder.recordScheduledRefreshRequested(
            accountName: account.name,
            activeAccount: account,
            savedAccounts: [account]
        )
        recorder.recordScheduledRefreshResult(
            accountName: account.name,
            error: "Refresh failed",
            activeAccount: account,
            savedAccounts: [account],
            uiEvidence: AccountSealScheduledRefreshUIEvidence(
                statusMessage: nil,
                menuItemCount: 0,
                lastMenuAction: nil,
                lastConfirmationRequest: nil
            )
        )

        #expect(!FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("manifest.json").path))
        let eventsURL = proofDirectory.appendingPathComponent("evidence/events.jsonl")
        let events = try String(contentsOf: eventsURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(events.compactMap { $0["event"] as? String } == [
            "scheduled_refresh_requested",
            "scheduled_refresh_failed",
        ])
    }
}
