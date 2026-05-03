import Foundation

enum CodexPillSealProofRecorderFactory {
    static let proofOutputPathEnvironmentKey = "CODEXPILL_SEAL_PROOF_OUTPUT"
    static let legacyScenarioEnvironmentKey = "CODEXPILL_VALIDATION_SCENARIO"

    @MainActor
    static func makeRecorder(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        registries: [CodexPillSealProofRecorderRegistry]? = nil
    ) -> CodexPillSealProofRecorder? {
        guard let legacyScenario = legacyScenario(environment: environment),
              let proofOutputPath = environment[proofOutputPathEnvironmentKey],
              !proofOutputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let outputDirectory = URL(fileURLWithPath: proofOutputPath)
        for registry in registries ?? defaultRegistries() {
            if let recorder = try? registry.makeRecorder(
                legacyScenario: legacyScenario,
                outputDirectory: outputDirectory
            ) {
                return recorder
            }
        }
        return nil
    }

    @MainActor
    private static func defaultRegistries() -> [CodexPillSealProofRecorderRegistry] {
        [
            AccountSealProofRecorderRegistry(),
            HostSealProofRecorderRegistry()
        ]
    }

    private static func legacyScenario(environment: [String: String]) -> String? {
        guard let scenario = environment[legacyScenarioEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scenario.isEmpty
        else {
            return nil
        }
        return scenario
    }
}
