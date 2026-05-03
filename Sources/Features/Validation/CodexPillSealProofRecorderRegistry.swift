import Foundation

@MainActor
protocol CodexPillSealProofRecorderRegistry {
    func makeRecorder(
        legacyScenario: String,
        outputDirectory: URL
    ) throws -> CodexPillSealProofRecorder?
}
