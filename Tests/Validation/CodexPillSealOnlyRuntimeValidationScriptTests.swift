import Foundation
import Testing

@Suite
struct CodexPillSealOnlyRuntimeValidationScriptTests {
    @Test
    func wrapperQuarantinesLegacyArtifactsAndPointsToSealArtifacts() throws {
        let repoRoot = Self.repoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/verify_account_switch_seal.sh")
        let artifactRoot = repoRoot
            .appendingPathComponent("build/verification/CodexPillSealOnlyRuntimeValidationScriptTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("switch-account-changes-active-account", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: artifactRoot.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        try "stale pass".write(to: artifactRoot.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        try "stale event".write(to: artifactRoot.appendingPathComponent("validation-events.jsonl"), atomically: true, encoding: .utf8)

        let fakeSeal = try Self.writeFakeSeal(
            repoRoot: repoRoot,
            name: "fake-seal-passed.sh",
            body: """
            #!/usr/bin/env bash
            set -euo pipefail
            output=""
            saw_adapter=0
            saw_proof_output=0
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --output)
                  output="$2"
                  shift 2
                  ;;
                --adapter)
                  saw_adapter=1
                  shift 2
                  ;;
                --proof-output)
                  saw_proof_output=1
                  shift 2
                  ;;
                *)
                  shift
                  ;;
              esac
            done
            test "${saw_adapter}" = "0"
            test "${saw_proof_output}" = "0"
            mkdir -p "${output}/proof" "${output}/reports" "${output}/adapter"
            printf '{"scenario":"switch-account-changes-active-account"}\\n' > "${output}/proof/manifest.json"
            printf '{"status":"passed"}\\n' > "${output}/reports/result.json"
            printf '# Seal Runner Report\\n' > "${output}/reports/report.md"
            printf '{"exitCode":0}\\n' > "${output}/adapter/exit.json"
            """
        )

        let result = try run(
            scriptURL,
            environment: [
                "AGENT_NAME": "CodexPillSealOnlyRuntimeValidationScriptTests",
                "ARTIFACT_ROOT": artifactRoot.path,
                "CODEXPILL_SEAL_COMMAND": fakeSeal.path
            ]
        )

        #expect(result.exitStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: artifactRoot.appendingPathComponent("summary.json").path))
        #expect(!FileManager.default.fileExists(atPath: artifactRoot.appendingPathComponent("validation-events.jsonl").path))

        let summaryData = try Data(contentsOf: artifactRoot.appendingPathComponent("codexpill-summary.json"))
        let summary = try #require(JSONSerialization.jsonObject(with: summaryData) as? [String: Any])
        #expect(summary["authoritativeRuntimeValidation"] as? String == "seal")
        #expect(summary["doesNotDefineIndependentVerdict"] as? Bool == true)
        #expect(summary["sealRunnerExitCode"] as? Int == 0)

        let authoritativeArtifacts = try #require(summary["authoritativeArtifacts"] as? [String: String])
        #expect(authoritativeArtifacts["proofManifest"] == "proof/manifest.json")
        #expect(authoritativeArtifacts["resultJson"] == "reports/result.json")
        #expect(authoritativeArtifacts["reportMarkdown"] == "reports/report.md")
        #expect(authoritativeArtifacts["adapterDirectory"] == "adapter/")
    }

    @Test
    func wrapperPropagatesIncompleteSealProofFailure() throws {
        let repoRoot = Self.repoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/verify_account_switch_seal.sh")
        let artifactRoot = repoRoot
            .appendingPathComponent("build/verification/CodexPillSealOnlyRuntimeValidationScriptTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("add-host-destination-validation-failed", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: artifactRoot.deletingLastPathComponent()) }

        let fakeSeal = try Self.writeFakeSeal(
            repoRoot: repoRoot,
            name: "fake-seal-incomplete.sh",
            body: """
            #!/usr/bin/env bash
            set -euo pipefail
            output=""
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --output)
                  output="$2"
                  shift 2
                  ;;
                *)
                  shift
                  ;;
              esac
            done
            mkdir -p "${output}/reports" "${output}/adapter"
            printf '{"exitCode":2}\\n' > "${output}/adapter/exit.json"
            exit 2
            """
        )

        let result = try run(
            scriptURL,
            environment: [
                "AGENT_NAME": "CodexPillSealOnlyRuntimeValidationScriptTests",
                "ARTIFACT_ROOT": artifactRoot.path,
                "CODEXPILL_SEAL_COMMAND": fakeSeal.path,
                "SCENARIO": "add-host-destination-validation-failed",
            ]
        )

        #expect(result.exitStatus == 2)

        let summaryData = try Data(contentsOf: artifactRoot.appendingPathComponent("codexpill-summary.json"))
        let summary = try #require(JSONSerialization.jsonObject(with: summaryData) as? [String: Any])
        #expect(summary["scenario"] as? String == "add-host-destination-validation-failed")
        #expect(summary["authoritativeRuntimeValidation"] as? String == "seal")
        #expect(summary["sealRunnerExitCode"] as? Int == 2)
        #expect((summary["sealArtifactGap"] as? String)?.contains("reports/result.json") == true)
    }

    @Test
    func wrapperSupportsAddHostValidationFailureSealScenario() throws {
        let repoRoot = Self.repoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/verify_account_switch_seal.sh")
        let artifactRoot = repoRoot
            .appendingPathComponent("build/verification/CodexPillSealOnlyRuntimeValidationScriptTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("add-host-destination-validation-failed", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: artifactRoot.deletingLastPathComponent()) }

        let fakeSeal = try Self.writeFakeSeal(
            repoRoot: repoRoot,
            name: "fake-seal-add-host-passed.sh",
            body: """
            #!/usr/bin/env bash
            set -euo pipefail
            output=""
            scenario=""
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --output)
                  output="$2"
                  shift 2
                  ;;
                --scenario)
                  scenario="$2"
                  shift 2
                  ;;
                *)
                  shift
                  ;;
              esac
            done
            mkdir -p "${output}/proof" "${output}/reports" "${output}/adapter"
            printf '{"scenario":"%s"}\\n' "${scenario}" > "${output}/proof/manifest.json"
            printf '{"status":"passed"}\\n' > "${output}/reports/result.json"
            printf '# Seal Runner Report\\n' > "${output}/reports/report.md"
            printf '{"exitCode":0}\\n' > "${output}/adapter/exit.json"
            """
        )

        let result = try run(
            scriptURL,
            environment: [
                "AGENT_NAME": "CodexPillSealOnlyRuntimeValidationScriptTests",
                "ARTIFACT_ROOT": artifactRoot.path,
                "CODEXPILL_SEAL_COMMAND": fakeSeal.path,
                "SCENARIO": "add-host-destination-validation-failed",
            ]
        )

        #expect(result.exitStatus == 0)

        let summaryData = try Data(contentsOf: artifactRoot.appendingPathComponent("codexpill-summary.json"))
        let summary = try #require(JSONSerialization.jsonObject(with: summaryData) as? [String: Any])
        #expect(summary["scenario"] as? String == "add-host-destination-validation-failed")
        #expect(summary["authoritativeRuntimeValidation"] as? String == "seal")
        #expect(summary["doesNotDefineIndependentVerdict"] as? Bool == true)
    }

    @Test
    func wrapperSupportsRemoteHostRefreshFailureSealScenario() throws {
        let repoRoot = Self.repoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/verify_account_switch_seal.sh")
        let artifactRoot = repoRoot
            .appendingPathComponent("build/verification/CodexPillSealOnlyRuntimeValidationScriptTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("remote-host-refresh-failure-preserves-fallback-state", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: artifactRoot.deletingLastPathComponent()) }

        let fakeSeal = try Self.writeFakeSeal(
            repoRoot: repoRoot,
            name: "fake-seal-remote-host-refresh-failure-passed.sh",
            body: """
            #!/usr/bin/env bash
            set -euo pipefail
            output=""
            scenario=""
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --output)
                  output="$2"
                  shift 2
                  ;;
                --scenario)
                  scenario="$2"
                  shift 2
                  ;;
                *)
                  shift
                  ;;
              esac
            done
            mkdir -p "${output}/proof" "${output}/reports" "${output}/adapter"
            printf '{"scenario":"%s"}\\n' "${scenario}" > "${output}/proof/manifest.json"
            printf '{"status":"passed"}\\n' > "${output}/reports/result.json"
            printf '# Seal Runner Report\\n' > "${output}/reports/report.md"
            printf '{"exitCode":0}\\n' > "${output}/adapter/exit.json"
            """
        )

        let result = try run(
            scriptURL,
            environment: [
                "AGENT_NAME": "CodexPillSealOnlyRuntimeValidationScriptTests",
                "ARTIFACT_ROOT": artifactRoot.path,
                "CODEXPILL_SEAL_COMMAND": fakeSeal.path,
                "SCENARIO": "remote-host-refresh-failure-preserves-fallback-state",
            ]
        )

        #expect(result.exitStatus == 0)

        let summaryData = try Data(contentsOf: artifactRoot.appendingPathComponent("codexpill-summary.json"))
        let summary = try #require(JSONSerialization.jsonObject(with: summaryData) as? [String: Any])
        #expect(summary["scenario"] as? String == "remote-host-refresh-failure-preserves-fallback-state")
        #expect(summary["authoritativeRuntimeValidation"] as? String == "seal")
        #expect(summary["doesNotDefineIndependentVerdict"] as? Bool == true)
    }

    @Test
    func wrapperSupportsBaselineMenuOpenSealScenario() throws {
        let repoRoot = Self.repoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/verify_account_switch_seal.sh")
        let artifactRoot = repoRoot
            .appendingPathComponent("build/verification/CodexPillSealOnlyRuntimeValidationScriptTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("baseline-menu-open-runtime-ready", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: artifactRoot.deletingLastPathComponent()) }

        let fakeSeal = try Self.writeFakeSeal(
            repoRoot: repoRoot,
            name: "fake-seal-baseline-menu-open-passed.sh",
            body: """
            #!/usr/bin/env bash
            set -euo pipefail
            output=""
            scenario=""
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --output)
                  output="$2"
                  shift 2
                  ;;
                --scenario)
                  scenario="$2"
                  shift 2
                  ;;
                *)
                  shift
                  ;;
              esac
            done
            mkdir -p "${output}/proof" "${output}/reports" "${output}/adapter"
            printf '{"scenario":"%s"}\\n' "${scenario}" > "${output}/proof/manifest.json"
            printf '{"status":"passed"}\\n' > "${output}/reports/result.json"
            printf '# Seal Runner Report\\n' > "${output}/reports/report.md"
            printf '{"exitCode":0}\\n' > "${output}/adapter/exit.json"
            """
        )

        let result = try run(
            scriptURL,
            environment: [
                "AGENT_NAME": "CodexPillSealOnlyRuntimeValidationScriptTests",
                "ARTIFACT_ROOT": artifactRoot.path,
                "CODEXPILL_SEAL_COMMAND": fakeSeal.path,
                "SCENARIO": "baseline-menu-open-runtime-ready",
            ]
        )

        #expect(result.exitStatus == 0)

        let summaryData = try Data(contentsOf: artifactRoot.appendingPathComponent("codexpill-summary.json"))
        let summary = try #require(JSONSerialization.jsonObject(with: summaryData) as? [String: Any])
        #expect(summary["scenario"] as? String == "baseline-menu-open-runtime-ready")
        #expect(summary["authoritativeRuntimeValidation"] as? String == "seal")
        #expect(summary["doesNotDefineIndependentVerdict"] as? Bool == true)
    }

    @Test
    func wrapperUsesSealConfigBackedAdapterAndProofOutputDefault() throws {
        let script = try String(contentsOf: Self.repoRoot().appendingPathComponent("scripts/verify_account_switch_seal.sh"))

        #expect(script.contains(#""${seal_command[@]}" run \"#))
        #expect(script.contains(#"--scenario "${SCENARIO}"#))
        #expect(script.contains(#"--output "${ARTIFACT_ROOT}""#))
        #expect(!script.contains(#"--adapter "${ADAPTER_PATH}""#))
        #expect(!script.contains(#"--proof-output "${PROOF_OUTPUT}""#))
    }

    @Test
    func sealRunConfigMapsSelectedScenariosToCodexPillAdapter() throws {
        let config = try String(contentsOf: Self.repoRoot().appendingPathComponent(".seal/run.yml"))

        #expect(config.contains("version: 1"))
        #expect(config.contains("switch-account-changes-active-account:"))
        #expect(config.contains("add-host-destination-validation-failed:"))
        #expect(config.contains("remote-host-refresh-failure-preserves-fallback-state:"))
        #expect(config.contains("baseline-menu-open-runtime-ready:"))
        #expect(config.contains("active-account-grouping-runtime-ready:"))
        #expect(config.components(separatedBy: "adapter: scripts/seal_run_adapter.sh").count == 6)
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func writeFakeSeal(repoRoot: URL, name: String, body: String) throws -> URL {
        let scriptURL = repoRoot.appendingPathComponent("build/tmp/\(name)")
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func run(_ executable: URL, environment: [String: String]) throws -> SealOnlyProcessResult {
        let process = Process()
        process.executableURL = executable
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return SealOnlyProcessResult(
            exitStatus: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private struct SealOnlyProcessResult {
    let exitStatus: Int32
    let stdout: String
    let stderr: String
}
