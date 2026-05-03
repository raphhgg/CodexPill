import Foundation
import SealRecorder

@MainActor
final class CodexPillSealProofSession {
    private let run: SealRun
    private var didFinish = false

    init(feature: SealFeature, scenarioID: ScenarioID, outputDirectory: URL) throws {
        try SealRecorder.register(features: [feature])
        run = try SealRecorder.startRun(
            feature: feature.id,
            scenario: scenarioID,
            executionMode: .liveUI,
            outputDirectory: outputDirectory
        )
    }

    var isFinished: Bool {
        didFinish
    }

    func recordEvent(
        _ eventName: String,
        step: String,
        invariantIds: [InvariantID],
        payload: JSONObject = [:]
    ) throws {
        guard !didFinish else { return }
        try run.recordEvent(eventName, step: step, invariantIds: invariantIds, payload: payload)
    }

    func recordSnapshot<Value: Encodable>(
        id: EvidenceID,
        path: String,
        value: Value
    ) throws {
        guard !didFinish else { return }
        try run.recordSnapshot(id: id, path: path, value: value)
    }

    func finish() throws {
        guard !didFinish else { return }
        try run.finish()
        didFinish = true
    }

    func cancelIfUnfinished() {
        guard !didFinish else { return }
        run.cancelIfUnfinished()
        didFinish = true
    }
}
