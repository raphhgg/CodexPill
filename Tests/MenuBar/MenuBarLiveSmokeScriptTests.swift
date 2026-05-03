import Foundation
import Testing

@Suite
struct MenuBarLiveSmokeScriptTests {
    @Test
    func sealBackedSmokeScriptSummariesUseSealVerdictSource() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repoRoot.appendingPathComponent("scripts/live_menubar_smoke.sh")
        let script = try String(contentsOf: scriptURL)

        for scenario in [
            "live-account-switch",
            "live-remote-host-switch",
            "live-add-account-name-dialog-cancelled",
            "live-add-host-destination-validation-failed",
            "live-scheduled-refresh"
        ] {
            #expect(script.contains(scenario))
        }

        #expect(script.contains("summary[\"verdict_source\"] = \"seal\""))
        #expect(script.contains("summary[\"status\"] = summary[\"sealVerifierPassed\"] ? \"passed\" : \"failed\""))
        #expect(script.contains("summary[\"sealResultPath\"] = \"seal-proof/result.json\""))
        #expect(script.contains("summary[\"sealReportPath\"] = \"seal-proof/report.md\""))
        #expect(script.contains("summary[\"sealReport\"] = {"))
        #expect(script.contains("\"source\" => \"seal-verifier\""))
        #expect(
            script.range(
                of: #"\$\{verifier_command\[@\]\}" --result-json --markdown-report --output-dir "\$\{SEAL_VERIFIER_OUTPUT_PATH\}" "\$\{proof_dir\}""#,
                options: .regularExpression
            ) != nil
        )
        #expect(script.contains("swift run seal-verifier --result-json --markdown-report --output-dir \"${verifier_output_dir}\" \"${proof_dir}\""))
        #expect(script.contains("\"diagnosticOnly\" => true"))
        #expect(script.contains("rm -rf \"${SEAL_PROOF_OUTPUT_PATH}\""))
        #expect(script.contains("rm -f \"${SEAL_VERIFIER_STDOUT_PATH}\" \"${SEAL_VERIFIER_STDERR_PATH}\""))
        #expect(!script.contains("summary[\"sealVerifierResultPath\"]"))
    }

    @Test
    func validationDocsDescribeCompatibilityStatusAsSealDerived() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let validationURL = repoRoot.appendingPathComponent("docs/VALIDATION.md")
        let validation = try String(contentsOf: validationURL)

        #expect(validation.contains("`summary.verdict_source` must be `\"seal\"`"))
        #expect(validation.contains("`summary.sealResultPath` must point to Seal's `result.json` artifact"))
        #expect(validation.contains("`summary.sealReportPath` must point to Seal's `report.md` artifact"))
        #expect(validation.contains("`summary.status` is only a temporary compatibility envelope"))
        #expect(validation.contains("`validation-events.jsonl` and legacy proof-sequence fields are diagnostic-only"))
    }
}
