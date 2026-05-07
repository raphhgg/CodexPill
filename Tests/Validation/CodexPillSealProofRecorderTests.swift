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
        recorder.recordCodexRelaunchRequested(targetAccount: business)
        recorder.recordPostSwitchRefreshCompleted(targetAccount: business, activeAccount: business, savedAccounts: [personal, business])

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
            "evidence/post-switch-refresh.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))

        let events = try proofEvents(in: proofDirectory)
        #expect(events.compactMap { $0["event"] as? String } == [
            "menu_action_dispatched",
            "switch_confirmation_presented",
            "switch_confirmation_accepted",
            "switch_workflow_started",
            "active_account_changed",
            "codex_relaunch_requested",
            "post_switch_refresh_completed",
        ])

        let postSwitchRefreshURL = proofDirectory.appendingPathComponent("evidence/post-switch-refresh.json")
        let postSwitchRefresh = try JSONSerialization.jsonObject(with: Data(contentsOf: postSwitchRefreshURL)) as? [String: Any]
        #expect(postSwitchRefresh?["relaunchRequested"] as? Bool == true)
        #expect(postSwitchRefresh?["refreshCompleted"] as? Bool == true)
        #expect(postSwitchRefresh?["activeAccountIdAfterRefresh"] as? String == business.id.uuidString)
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

        let events = try proofEvents(in: proofDirectory)
        #expect(events.compactMap { $0["event"] as? String } == [
            "menu_action_dispatched",
            "add_host_setup_presented",
            "add_host_validation_started",
            "add_host_validation_failed",
        ])

        let hostValidationURL = proofDirectory.appendingPathComponent("evidence/host-validation-snapshot.json")
        let hostValidation = try JSONSerialization.jsonObject(with: Data(contentsOf: hostValidationURL)) as? [String: Any]
        #expect(hostValidation?["validationResult"] as? String == "failed")
        #expect(hostValidation?["hostName"] as? String == "codexpill-validation.invalid")
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

        let events = try proofEvents(in: proofDirectory)
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
    func proofRecorderEmitsRemoteHostRefreshFailureProof() throws {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealProof-\(UUID().uuidString)", isDirectory: true)
        let proofRecorder = try #require(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "persisted_host_refresh_failure",
        ]))
        let recorder = try #require(proofRecorder.host)

        recorder.recordRemoteHostRefreshStarted(hostName: "buildbox", fallbackAccountName: "Business 2")
        recorder.recordRemoteHostRefreshFailed(hostName: "buildbox", message: "ssh: connection refused")
        recorder.recordRemoteHostMarkedDisconnected(hostName: "buildbox", fallbackAccountName: "Business 2")

        let manifestURL = proofDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let runMetadata = manifest?["run"] as? [String: Any]
        let evidence = manifest?["evidence"] as? [[String: Any]]

        #expect(runMetadata?["feature"] as? String == "hosts")
        #expect(runMetadata?["scenario"] as? String == "remote-host-refresh-failure-preserves-fallback-state")
        #expect(evidence?.compactMap { $0["path"] as? String } == [
            "evidence/host-before-refresh.json",
            "evidence/events.jsonl",
            "evidence/host-after-refresh.json",
        ])
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/events.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/host-before-refresh.json").path))
        #expect(FileManager.default.fileExists(atPath: proofDirectory.appendingPathComponent("evidence/host-after-refresh.json").path))

        let events = try proofEvents(in: proofDirectory)
        #expect(events.compactMap { $0["event"] as? String } == [
            "remote_host_refresh_started",
            "remote_host_refresh_failed",
            "remote_host_marked_disconnected",
        ])

        let hostAfterURL = proofDirectory.appendingPathComponent("evidence/host-after-refresh.json")
        let hostAfter = try JSONSerialization.jsonObject(with: Data(contentsOf: hostAfterURL)) as? [String: Any]
        #expect(hostAfter?["connectionState"] as? String == "disconnected")
        #expect(hostAfter?["activeAccountPresented"] as? Bool == false)
        #expect(hostAfter?["remoteActiveCardVisible"] as? Bool == false)
        #expect(hostAfter?["fallbackAccountName"] as? String == "Business 2")
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

        let events = try proofEvents(in: proofDirectory)
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
        let events = try proofEvents(in: proofDirectory)
        #expect(events.compactMap { $0["event"] as? String } == [
            "scheduled_refresh_requested",
            "scheduled_refresh_failed",
        ])
    }

    @Test
    func factoryReturnsNoRecorderWithoutCompleteCodexPillActivationEnvironment() {
        let proofDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealProof-\(UUID().uuidString)", isDirectory: true)

        #expect(CodexPillSealProofRecorderFactory.makeRecorder(environment: [:]) == nil)
        #expect(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
        ]) == nil)
        #expect(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: "   ",
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "live-account-switch",
        ]) == nil)
        #expect(CodexPillSealProofRecorderFactory.makeRecorder(environment: [
            CodexPillSealProofRecorderFactory.proofOutputPathEnvironmentKey: proofDirectory.path,
            CodexPillSealProofRecorderFactory.legacyScenarioEnvironmentKey: "   ",
        ]) == nil)
    }

    private func proofEvents(in proofDirectory: URL) throws -> [[String: Any]] {
        let eventsURL = proofDirectory.appendingPathComponent("evidence/events.jsonl")
        return try String(contentsOf: eventsURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }
}
