import Foundation
import SealRecorder

enum HostSealScenarioCatalog {
    static func feature(scenarios: [HostSealScenario]) throws -> SealFeature {
        try SealFeature(
            id: FeatureID("hosts"),
            scenarios: try scenarios.map(makeScenario)
        )
    }

    private static func makeScenario(_ scenario: HostSealScenario) throws -> SealScenario {
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

        guard let remoteHostRefreshFailureID = scenario.remoteHostRefreshFailureID,
              let remoteHostRefreshFailureExpectation = scenario.remoteHostRefreshFailureExpectation
        else {
            throw HostSealScenarioCatalogError.unsupportedScenario(String(describing: scenario.id))
        }

        return try SealScenario(
            id: scenario.id,
            scenarioType: .failurePath,
            supportedExecutionModes: [.liveUI],
            expectations: [
                try SealExpectation(
                    text: remoteHostRefreshFailureExpectation,
                    invariants: [
                        SealInvariantRef(
                            id: remoteHostRefreshFailureID,
                            requiredEvidence: [
                                EvidenceRequirement(id: EvidenceID("events"), kind: .eventStream),
                                EvidenceRequirement(id: EvidenceID("host_before_refresh"), kind: .snapshot),
                                EvidenceRequirement(id: EvidenceID("host_after_refresh"), kind: .snapshot)
                            ],
                            rule: scenario.remoteHostRefreshFailureRule
                        )
                    ]
                )
            ]
        )
    }
}

struct HostSealScenario {
    private static let addHostValidationDestination = "codexpill-validation.invalid"
    private static let remoteHostSwitchHostName = "buildbox"
    private static let remoteHostRefreshFailureHostName = "buildbox"
    private static let remoteHostRefreshFailureFallbackAccountName = "Business 2"

    let id: ScenarioID
    let hostValidationID: InvariantID?
    let hostExpectation: String?
    let remoteHostSwitchID: InvariantID?
    let remoteHostSwitchExpectation: String?
    let remoteHostRefreshFailureID: InvariantID?
    let remoteHostRefreshFailureExpectation: String?

    var hostInvariantIDs: [InvariantID] {
        hostValidationID.map { [$0] } ?? []
    }

    var remoteHostSwitchInvariantIDs: [InvariantID] {
        remoteHostSwitchID.map { [$0] } ?? []
    }

    var remoteHostRefreshFailureInvariantIDs: [InvariantID] {
        remoteHostRefreshFailureID.map { [$0] } ?? []
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

    var remoteHostRefreshFailureRule: SealRule {
        .all([
            .eventSequence([
                EventExpectation("remote_host_refresh_started", payload: [
                    "hostName": .string(Self.remoteHostRefreshFailureHostName),
                    "fallbackAccountName": .string(Self.remoteHostRefreshFailureFallbackAccountName)
                ]),
                EventExpectation("remote_host_refresh_failed", payload: [
                    "hostName": .string(Self.remoteHostRefreshFailureHostName)
                ]),
                EventExpectation("remote_host_marked_disconnected", payload: [
                    "hostName": .string(Self.remoteHostRefreshFailureHostName),
                    "fallbackAccountName": .string(Self.remoteHostRefreshFailureFallbackAccountName)
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
    }

    private init(
        id: ScenarioID,
        hostValidationID: InvariantID? = nil,
        hostExpectation: String? = nil,
        remoteHostSwitchID: InvariantID? = nil,
        remoteHostSwitchExpectation: String? = nil,
        remoteHostRefreshFailureID: InvariantID? = nil,
        remoteHostRefreshFailureExpectation: String? = nil
    ) {
        self.id = id
        self.hostValidationID = hostValidationID
        self.hostExpectation = hostExpectation
        self.remoteHostSwitchID = remoteHostSwitchID
        self.remoteHostSwitchExpectation = remoteHostSwitchExpectation
        self.remoteHostRefreshFailureID = remoteHostRefreshFailureID
        self.remoteHostRefreshFailureExpectation = remoteHostRefreshFailureExpectation
    }

    init?(legacyScenario: String) {
        switch legacyScenario {
        case "live-add-host-destination-validation-failed", "live-add-host-prompt":
            self = .addHostDestinationValidationFailed
        case "live-remote-host-switch":
            self = .switchAccountOnHostChangesRemoteActiveAccount
        case "persisted_host_refresh_failure", "live-remote-host-refresh-failure":
            self = .remoteHostRefreshFailurePreservesFallbackState
        default:
            return nil
        }
    }

    static let addHostDestinationValidationFailed = HostSealScenario(
        id: ScenarioID("add-host-destination-validation-failed"),
        hostValidationID: InvariantID("hosts.add_host.destination_validation_failed"),
        hostExpectation: "Entering an invalid Add Host destination emits validation feedback"
    )

    static let switchAccountOnHostChangesRemoteActiveAccount = HostSealScenario(
        id: ScenarioID("switch-account-on-host-changes-remote-active-account"),
        remoteHostSwitchID: InvariantID("hosts.switch_account_on_host.changes_remote_active_account"),
        remoteHostSwitchExpectation: "Switching account through a host submenu changes that host's active remote account"
    )

    static let remoteHostRefreshFailurePreservesFallbackState = HostSealScenario(
        id: ScenarioID("remote-host-refresh-failure-preserves-fallback-state"),
        remoteHostRefreshFailureID: InvariantID("hosts.remote_host_refresh_failure.preserves_fallback_state"),
        remoteHostRefreshFailureExpectation: "A remote host refresh failure preserves fallback state while marking the host disconnected"
    )
}

enum HostSealScenarioCatalogError: Error {
    case unsupportedScenario(String)
}
