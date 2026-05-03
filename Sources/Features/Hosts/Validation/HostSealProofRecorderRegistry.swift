import Foundation

@MainActor
struct HostSealProofRecorderRegistry: CodexPillSealProofRecorderRegistry {
    func makeRecorder(
        legacyScenario: String,
        outputDirectory: URL
    ) throws -> CodexPillSealProofRecorder? {
        guard let scenario = HostSealScenario(legacyScenario: legacyScenario) else {
            return nil
        }

        let hostRecorder = try HostSealProofRecorder(
            scenario: scenario,
            outputDirectory: outputDirectory
        )
        return CodexPillSealProofRecorder(hostRecorder: hostRecorder)
    }
}
