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
        #expect(script.contains("\"diagnosticOnly\" => true"))
        #expect(script.contains("rm -rf \"${SEAL_PROOF_OUTPUT_PATH}\""))
        #expect(script.contains("rm -f \"${SEAL_VERIFIER_STDOUT_PATH}\" \"${SEAL_VERIFIER_STDERR_PATH}\" \"${SEAL_VERIFIER_RESULT_PATH}\""))
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
        #expect(validation.contains("`summary.status` is only a temporary compatibility envelope"))
        #expect(validation.contains("`validation-events.jsonl` and legacy proof-sequence fields are diagnostic-only"))
    }
}
