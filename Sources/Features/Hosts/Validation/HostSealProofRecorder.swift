import Foundation
import os
import SealRecorder

private let hostSealProofRecorderLogger = Logger(
    subsystem: "com.raphhgg.codexpill",
    category: "SealValidation"
)

@MainActor
final class HostSealProofRecorder: HostValidationRecorder {
    private let scenario: HostSealScenario
    private let session: CodexPillSealProofSession

    init(scenario: HostSealScenario, outputDirectory: URL) throws {
        self.scenario = scenario
        self.session = try CodexPillSealProofSession(
            feature: try HostSealScenarioCatalog.feature(scenarios: [scenario]),
            scenarioID: scenario.id,
            outputDirectory: outputDirectory
        )
    }

    func recordAddHostMenuAction() {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "menu_action_dispatched",
                step: "menu_action_dispatch",
                invariantIds: scenario.hostInvariantIDs,
                payload: ["action": .string("addHost")]
            )
        } catch {
            hostSealProofRecorderLogger.error("Failed to record Seal add-host menu action proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordAddHostSetupPresented() {
        recordHostEvent("add_host_setup_presented", step: "add_host_setup")
    }

    func recordAddHostValidationStarted(hostName: String) {
        recordHostEvent(
            "add_host_validation_started",
            step: "add_host_validation",
            payload: ["hostName": .string(hostName)]
        )
    }

    func recordAddHostValidationFailed(hostName: String, message: String) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "add_host_validation_failed",
                step: "add_host_validation",
                invariantIds: scenario.hostInvariantIDs,
                payload: [
                    "hostName": .string(hostName),
                    "message": .string(message)
                ]
            )
            try session.recordSnapshot(
                id: EvidenceID("host_validation_snapshot"),
                path: "evidence/host-validation-snapshot.json",
                value: HostSealValidationSnapshot(
                    hostName: hostName,
                    validationResult: "failed",
                    message: message
                )
            )
            try session.finish()
        } catch {
            hostSealProofRecorderLogger.error("Failed to finish Seal add-host validation proof: \(error.localizedDescription, privacy: .public)")
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
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "remote_host_active_account_changed",
                step: "remote_host_switch_result",
                invariantIds: scenario.remoteHostSwitchInvariantIDs,
                payload: [
                    "targetName": .string(targetName),
                    "hostName": .string(hostName)
                ]
            )
            try session.finish()
        } catch {
            hostSealProofRecorderLogger.error("Failed to finish Seal remote-host switch proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordRemoteHostRefreshStarted(hostName: String, fallbackAccountName: String) {
        guard !session.isFinished else { return }
        do {
            try session.recordSnapshot(
                id: EvidenceID("host_before_refresh"),
                path: "evidence/host-before-refresh.json",
                value: HostSealRefreshFailureSnapshot(
                    hostName: hostName,
                    fallbackAccountName: fallbackAccountName,
                    connectionState: "connected",
                    activeAccountPresented: true,
                    remoteActiveCardVisible: true,
                    failureMessage: nil
                )
            )
            try session.recordEvent(
                "remote_host_refresh_started",
                step: "remote_host_refresh_start",
                invariantIds: scenario.remoteHostRefreshFailureInvariantIDs,
                payload: [
                    "hostName": .string(hostName),
                    "fallbackAccountName": .string(fallbackAccountName)
                ]
            )
        } catch {
            hostSealProofRecorderLogger.error("Failed to record Seal remote-host refresh start proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordRemoteHostRefreshFailed(hostName: String, message: String) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "remote_host_refresh_failed",
                step: "remote_host_refresh_result",
                invariantIds: scenario.remoteHostRefreshFailureInvariantIDs,
                payload: [
                    "hostName": .string(hostName),
                    "message": .string(message)
                ]
            )
        } catch {
            hostSealProofRecorderLogger.error("Failed to record Seal remote-host refresh failure proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordRemoteHostMarkedDisconnected(hostName: String, fallbackAccountName: String) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                "remote_host_marked_disconnected",
                step: "remote_host_state_update",
                invariantIds: scenario.remoteHostRefreshFailureInvariantIDs,
                payload: [
                    "hostName": .string(hostName),
                    "fallbackAccountName": .string(fallbackAccountName)
                ]
            )
            try session.recordSnapshot(
                id: EvidenceID("host_after_refresh"),
                path: "evidence/host-after-refresh.json",
                value: HostSealRefreshFailureSnapshot(
                    hostName: hostName,
                    fallbackAccountName: fallbackAccountName,
                    connectionState: "disconnected",
                    activeAccountPresented: false,
                    remoteActiveCardVisible: false,
                    failureMessage: "ssh: connection refused"
                )
            )
            try session.finish()
        } catch {
            hostSealProofRecorderLogger.error("Failed to finish Seal remote-host refresh failure proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelIfUnfinished() {
        session.cancelIfUnfinished()
    }

    private func recordHostEvent(_ eventName: String, step: String, payload: JSONObject = [:]) {
        guard !session.isFinished else { return }
        do {
            try session.recordEvent(
                eventName,
                step: step,
                invariantIds: scenario.hostInvariantIDs,
                payload: payload
            )
        } catch {
            hostSealProofRecorderLogger.error("Failed to record Seal add-host event proof: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordRemoteHostSwitchEvent(
        _ eventName: String,
        step: String,
        targetName: String,
        hostName: String,
        additionalPayload: JSONObject = [:]
    ) {
        guard !session.isFinished else { return }
        var payload: JSONObject = [
            "targetName": .string(targetName),
            "hostName": .string(hostName)
        ]
        for (key, value) in additionalPayload {
            payload[key] = value
        }
        do {
            try session.recordEvent(
                eventName,
                step: step,
                invariantIds: scenario.remoteHostSwitchInvariantIDs,
                payload: payload
            )
        } catch {
            hostSealProofRecorderLogger.error("Failed to record Seal remote-host switch event proof: \(error.localizedDescription, privacy: .public)")
        }
    }
}
