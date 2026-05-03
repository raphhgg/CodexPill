import Foundation

@MainActor
struct AccountSealProofRecorderRegistry: CodexPillSealProofRecorderRegistry {
    func makeRecorder(
        legacyScenario: String,
        outputDirectory: URL
    ) throws -> CodexPillSealProofRecorder? {
        guard let scenario = AccountSealScenario(legacyScenario: legacyScenario) else {
            return nil
        }

        let accountRecorder = try AccountSealProofRecorder(
            scenario: scenario,
            outputDirectory: outputDirectory
        )
        return CodexPillSealProofRecorder(accountRecorder: accountRecorder)
    }
}
