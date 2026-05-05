import Foundation
import Testing

@Suite
struct CodexPillSealRunAdapterScriptTests {
    @Test
    func adapterAcceptsSealRunnerContractAndInvokesCodexPillProofEmitter() throws {
        let script = try Self.adapterScriptContents()

        #expect(script.contains("--scenario"))
        #expect(script.contains("--proof-output"))
        #expect(script.contains("--artifact-root"))
        #expect(script.contains("switch-account-changes-active-account"))
        #expect(script.contains("OUTPUT_DIR=\"${PROOF_OUTPUT}\" make emit-account-switch-proof"))
        #expect(script.contains("codexpill-adapter.log"))
        #expect(script.contains("codexpill-scenario.json"))
        #expect(script.contains("${ARTIFACT_ROOT}/adapter"))
    }

    @Test
    func adapterRejectsUnsupportedScenarioWithAdapterDiagnostics() throws {
        let repoRoot = Self.repoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/seal_run_adapter.sh")
        let artifactRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillSealRunAdapterScriptTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: artifactRoot) }

        let result = try run(
            scriptURL,
            arguments: [
                "--scenario", "unsupported-scenario",
                "--proof-output", artifactRoot.appendingPathComponent("proof", isDirectory: true).path,
                "--artifact-root", artifactRoot.path
            ]
        )

        #expect(result.exitStatus == 64)
        #expect(result.stderr.contains("Unsupported CodexPill Seal runner scenario: unsupported-scenario"))

        let logURL = artifactRoot.appendingPathComponent("adapter/codexpill-adapter.log")
        let metadataURL = artifactRoot.appendingPathComponent("adapter/codexpill-scenario.json")
        #expect(FileManager.default.fileExists(atPath: logURL.path))
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
        #expect(try String(contentsOf: logURL).contains("unsupported scenario: unsupported-scenario"))
        #expect(try String(contentsOf: metadataURL).contains(#""status": "unsupported""#))
    }

    private static func adapterScriptContents() throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent("scripts/seal_run_adapter.sh"))
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func run(_ executable: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ProcessResult(
            exitStatus: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private struct ProcessResult {
    let exitStatus: Int32
    let stdout: String
    let stderr: String
}
