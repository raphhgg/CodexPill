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

        guard let remoteHostSwitchID = scenario.remoteHostSwitchID,
              let remoteHostSwitchExpectation = scenario.remoteHostSwitchExpectation
        else {
            throw HostSealScenarioCatalogError.unsupportedScenario(String(describing: scenario.id))
        }

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
}

struct HostSealScenario {
    private static let addHostValidationDestination = "codexpill-validation.invalid"
    private static let remoteHostSwitchHostName = "buildbox"

    let id: ScenarioID
    let hostValidationID: InvariantID?
    let hostExpectation: String?
    let remoteHostSwitchID: InvariantID?
    let remoteHostSwitchExpectation: String?

    var hostInvariantIDs: [InvariantID] {
        hostValidationID.map { [$0] } ?? []
    }

    var remoteHostSwitchInvariantIDs: [InvariantID] {
        remoteHostSwitchID.map { [$0] } ?? []
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

    private init(
        id: ScenarioID,
        hostValidationID: InvariantID? = nil,
        hostExpectation: String? = nil,
        remoteHostSwitchID: InvariantID? = nil,
        remoteHostSwitchExpectation: String? = nil
    ) {
        self.id = id
        self.hostValidationID = hostValidationID
        self.hostExpectation = hostExpectation
        self.remoteHostSwitchID = remoteHostSwitchID
        self.remoteHostSwitchExpectation = remoteHostSwitchExpectation
    }

    init?(legacyScenario: String) {
        switch legacyScenario {
        case "live-add-host-destination-validation-failed", "live-add-host-prompt":
            self = .addHostDestinationValidationFailed
        case "live-remote-host-switch":
            self = .switchAccountOnHostChangesRemoteActiveAccount
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
}

enum HostSealScenarioCatalogError: Error {
    case unsupportedScenario(String)
}
