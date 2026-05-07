# Seal Runtime Validation Migration Plan

## Purpose

CodexPill is moving runtime/live validation toward Seal while keeping lower-level CodexPill tests for behavior that they prove better than runtime proof artifacts.

The end goal is:

- CodexPill relies on Seal for runtime/live validation verdicts.
- CodexPill feature docs under `docs/features/` are mapped to Seal scenarios where runtime proof is the right owner.
- Seal result JSON and Markdown reports become the reviewable validation artifacts.
- Legacy CodexPill runtime validation gates are removed or demoted to diagnostics.
- The remaining CodexPill test suite is reviewed for real value after runtime validation moves to Seal.

## Boundary Decision

For the Phase 14 stable-candidate boundary, CodexPill still owns
proof-producing entrypoints and product scenario semantics. Seal owns runner
orchestration, proof verification, reporting, and the authoritative pass/fail
verdict once a scenario adapter is resolved from `.seal/run.yml`.

Accepted shape for selected Seal-backed flows:

```text
seal run --scenario <scenario>
Seal resolves the CodexPill adapter from .seal/run.yml.
CodexPill emits proof through SealRecorder into the runner artifact root.
Seal verifies the proof and writes reports/result.json plus reports/report.md.
```

The direct proof-emitter and `seal-verifier` path remains internal development
support for proof shape work. It is not the runtime validation authority for
selected Seal-backed flows.

The compatibility Make wrappers may still write `codexpill-summary.json`, but
that file is only a pointer derived from Seal artifacts. It must not define an
independent verdict, and legacy CodexPill artifacts such as `summary.json` and
`validation-events.jsonl` are diagnostic-only for selected Seal-backed flows.

## Issue Contracts

### 1. CodexPill Seal-only runtime validation path

User story:

As a CodexPill maintainer, I want currently Seal-backed runtime/live validation flows to rely on Seal as the only pass/fail authority, so I can inspect the pure Seal integration without legacy validation logic hiding whether Seal is good enough.

Scope:

- `live-add-account-name-dialog-cancelled`
- `live-account-switch`
- `live-add-host-destination-validation-failed`
- `live-remote-host-switch`
- `live-scheduled-refresh`

Acceptance:

- Seal-backed scenarios fail when Seal proof is missing.
- Seal-backed scenarios fail when `seal-verifier` rejects the proof.
- Seal-backed scenarios cannot pass solely from `validation-events.jsonl` or legacy proof-sequence checks.
- `validation-events.jsonl` may still be emitted, but is diagnostic-only.
- `codexpill-summary.json` may remain temporarily for Makefile wrappers, but
  must be derived from Seal artifacts and must not define an independent verdict.
- Compatibility summary includes explicit Seal authority fields and points to
  `proof/`, `reports/result.json`, `reports/report.md`, and `adapter/`.
- Docs state compatibility summaries are temporary pointers, not the
  Seal-native report API.
- Fresh artifact handling prevents stale Seal or stale legacy artifacts from influencing verdicts.
- Non-Seal-backed flows are not silently converted or broken.

Out of scope:

- Deleting legacy event emission.
- Adding new Seal scenarios.
- Adding CI workflow.
- Seal Markdown report generation.
- Full test-suite cleanup.

### 2. CodexPill account-switch proof emitter for Seal V1 validation

User story:

As a Seal/CodexPill maintainer, I want CodexPill to emit a deterministic Seal proof for account switching with minimal extra harness code, so the stable-candidate `seal run` boundary validates a real business rule while CodexPill keeps its product semantics.

Business rule:

`accounts.switch_account.menu_action_changes_active_account`

Acceptance:

- The proof emitter is least invasive and internal-facing, not a polished user CLI.
- It validates an existing CodexPill business rule.
- It does not use live UI automation or Accessibility permissions.
- It does not depend on SSH, browser auth, app-server, or real user Codex auth.
- It uses isolated fixture-owned paths only.
- It emits proof to a caller-provided output directory.
- The proof passes with `seal-verifier`.
- The scenario uses a non-live execution mode.
- Docs explicitly say this is a V1 boundary validation slice.
- Docs explicitly describe direct proof-emitter commands as internal development
  paths, not runtime validation authority.
- Any friction found while implementing the client-owned proof emitter is
  recorded as input for future runner/orchestrator improvements.

Out of scope:

- Replacing `seal run --scenario ...` as the normal selected-flow reviewer
  command.
- CI-only workflow optimization.
- Live UI CI.
- Markdown report generation.
- Removing legacy runtime gates.
- Full feature coverage map.

### 3. Seal verifier Markdown report output

User story:

As a maintainer reviewing validation evidence, I want `seal-verifier` to emit a readable Markdown report next to result JSON, so I can attach or link human-readable proof evidence in PRs, Linear issues, and release reviews.

Acceptance:

- `--markdown-report` requires `--output-dir`.
- `seal-verifier` verifies the proof once and writes report output from the same result.
- Existing `--result-json` behavior remains backward-compatible.
- The Markdown report includes run verdict, feature, scenario, execution mode, and run id.
- It includes expectation verdicts and invariant verdicts.
- It includes readable diagnostics for failed or invalid proofs.
- It includes evidence IDs, evidence kinds, and proof-relative paths.
- It includes a visual artifacts section.
- Visual artifact links are included when present.
- If no screenshots or videos are present, the report says visual artifacts were not captured.
- The report links artifacts by path; it does not embed binary content.
- The report does not dump raw snapshot/event payloads by default.
- Docs state Markdown is human-readable review evidence, not the CI gate.
- Tests cover passed proof, failed or invalid proof, and visual-artifact/no-visual-artifact rendering.

Out of scope:

- Standalone `seal-report`.
- HTML output.
- Publishing to Linear or GitHub.
- Public artifact hosting.
- Mandatory screenshot or video capture.
- CodexPill-specific report sections.

### 4. CodexPill Seal report artifact adoption

User story:

As a CodexPill maintainer or reviewer, I want CodexPill validation summaries to point to Seal's machine and Markdown reports, so I can inspect validation evidence without parsing raw harness logs.

Dependency:

- Depends on Seal verifier Markdown report output.

Acceptance:

- CodexPill does not duplicate Seal report rendering logic.
- Seal-backed summaries include path to `seal-result.json`.
- Seal-backed summaries include path to `seal-report.md`.
- Summary identifies `verdict_source: "seal"`.
- Top-level `status` remains compatibility-only and is derived from Seal verdict.
- Legacy validation event artifacts, if present, are labelled diagnostic-only.
- Artifact paths are relative or stable enough for local, CI, and agent collection.
- Docs explain how to attach or link the Markdown report in PRs or Linear issue updates.

Out of scope:

- CodexPill generating Markdown itself.
- Uploading directly to Linear or GitHub.
- Removing legacy event emission.
- Adding screenshots or videos beyond whatever Seal already links.

### 5. CodexPill feature-to-Seal scenario coverage map

User story:

As a CodexPill maintainer, I want every runtime/live business claim in `docs/features/` mapped to Seal coverage status, so we can migrate legacy validation intentionally and know what remains outside Seal.

Acceptance:

- Every CodexPill feature area under `docs/features/` is reviewed.
- Every runtime/live business claim is categorized.
- Existing Seal-backed scenarios are linked to their feature claims.
- Legacy runtime validation flows not yet covered by Seal are listed.
- Lower-layer-owned claims include rationale for not moving to Seal.
- Manual, OS, or environmental claims are explicit.
- The map identifies a prioritized backlog for future Seal scenario migrations.
- Seal docs link to the map only as adoption pressure or release-readiness context.
- No scenarios are implemented in this slice.
- No tests are deleted in this slice.

Coverage categories:

- Seal runtime/live scenario exists.
- Seal scenario needed.
- Lower-layer test owns this better.
- Manual/OS/environmental validation.
- Deferred or not currently validated.

### 6. CodexPill test-suite relevance review after Seal runtime migration

User story:

As a CodexPill maintainer, I want a documented review of which tests still add value after Seal owns runtime/live validation, so we can reduce duplicate validation without deleting useful lower-layer coverage.

Acceptance:

- Review covers main CodexPill test suites.
- Review is grounded in `docs/features/`, `docs/VALIDATION.md`, and the Seal coverage map.
- Lower-layer tests are not removed or devalued just because Seal exists.
- Duplicate runtime/live validation coverage is identified.
- Tests with distinct failure modes remain explicitly justified.
- Mutating/live-auth/real-user-state tests are flagged.
- Output is actionable as follow-up issues.
- No bulk test deletion happens in this slice.

Output:

- suites reviewed
- feature claims/invariants considered
- keep/delete/rewrite/migrate categories
- rationale per category
- risky tests that may mutate real user state
- follow-up cleanup or migration issue candidates

## Recommended Order

1. CodexPill Seal-only runtime validation path.
2. CodexPill account-switch proof emitter for Seal V1 validation.
3. Seal verifier Markdown report output.
4. CodexPill Seal report artifact adoption.
5. CodexPill feature-to-Seal scenario coverage map.
6. CodexPill test-suite relevance review after Seal runtime migration.

## Open Follow-Up

After this migration program, decide whether Seal should prioritize additional
runner/orchestrator improvements around the stable-candidate `seal run` command
and client scenario-adapter contract.
