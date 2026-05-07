# Seal V1 Boundary Validation

This document records CodexPill's internal proof emitter for the Seal V1 adoption boundary.

The current V1 boundary is deliberately split:

- CodexPill owns a proof-producing entrypoint for a real product rule.
- Seal owns verification of the emitted proof through `seal-verifier`.

This slice validates `accounts.switch_account.menu_action_changes_active_account`.
As of RGR-253, the selected runtime validation gate for
`switch-account-changes-active-account` is the explicit `seal run` path; the
direct emitter remains useful for lower-level proof-emitter development only.

## Account Switch Proof Emitter

The internal emitter is `CodexPillProofEmitter`. It is intentionally narrow and is not a polished user CLI.

Run it through the repo-local Makefile:

```bash
OUTPUT_DIR=build/validation-proof/account-switch make emit-account-switch-proof
```

Then verify the proof with Seal:

```bash
swift run --package-path ../Seal seal-verifier --verbose build/validation-proof/account-switch
```

The emitter uses `.integration` execution mode, deterministic fixture accounts, and a caller-provided proof output directory. It does not use Accessibility, browser auth, SSH, app-server reads, live UI automation, or real user Codex auth.

The emitter refuses to write under default Codex production data directories:

- `~/.codex`
- `~/Library/Application Support/Codex`
- `~/Library/Application Support/CodexPill`

## Seal-Only Runtime Validation

CodexPill has a client-owned adapter for Seal's provisional `seal run` command.
Run the selected account-switch runtime validation through the repo-local
Makefile target:

```bash
AGENT_NAME=symphony-RGR-253 make verify-account-switch-seal
```

The adapter accepts Seal's generic `--scenario`, `--proof-output`, and
`--artifact-root` inputs, resolves the CodexPill-owned deterministic account
switch scenario, emits proof through `make emit-account-switch-proof`, and writes
CodexPill diagnostics under the runner-owned `adapter/` directory.

The authoritative artifacts for this selected flow are:

- `proof/`
- `reports/result.json`
- `reports/report.md`
- `adapter/`

`codexpill-summary.json` is compatibility-only. It points report consumers to
Seal artifacts, records the Seal runner exit code, and marks legacy CodexPill
runtime outputs such as `summary.json` and `validation-events.jsonl` as
non-authoritative. The wrapper removes stale legacy output for this scenario
before invoking `seal run`, so old CodexPill runtime artifacts cannot make the
selected flow pass.

The direct proof-emitter development path remains:

```bash
OUTPUT_DIR=build/validation-proof/account-switch make emit-account-switch-proof
swift run --package-path /Users/raphh/Projects/Seal seal-verifier \
  --result-json \
  --markdown-report \
  --output-dir build/validation-proof/account-switch-report \
  build/validation-proof/account-switch
```

RGR-253 decision: for `switch-account-changes-active-account`, Seal runner
artifacts are good enough to be the runtime validation authority. The reports
give the required machine-readable and human-readable evidence, and the runner
exit codes distinguish failed proof, invalid or incomplete proof, adapter
failure, and runner/setup error. The remaining friction is adapter ceremony and
build cost, not missing report authority.

The first failure path exercised by this prototype is adapter-side scenario
resolution: unsupported scenarios exit non-zero and write diagnostics under
`adapter/`. Invalid-proof behavior remains owned by Seal's runner and verifier
tests for now because forcing this CodexPill adapter to emit malformed proof
would add test-only behavior to the product adapter.

## Runner/Orchestrator Friction

## End-to-End Adapter Proof

RGR-222 proved the deterministic account-switch scenario through Seal's full
provisional runner path on 2026-05-05 using local Seal checkout `f789a3d`:

```bash
AGENT_NAME=symphony-RGR-222 OUTPUT_DIR=build/RGR-222/direct/proof make emit-account-switch-proof
swift run --package-path /Users/raphh/Projects/Seal seal-verifier \
  --result-json \
  --markdown-report \
  --output-dir build/RGR-222/direct/reports \
  build/RGR-222/direct/proof
swift run --package-path /Users/raphh/Projects/Seal seal run \
  --scenario switch-account-changes-active-account \
  --output build/RGR-222/seal-run \
  --proof-output build/RGR-222/seal-run/proof \
  --adapter scripts/seal_run_adapter.sh
```

Both paths passed the same Seal verifier rule:

- `accounts.switch_account.menu_action_changes_active_account`
- event sequence:
  `menu_action_dispatched -> switch_confirmation_presented -> switch_confirmation_accepted -> switch_workflow_started -> active_account_changed`
- snapshot comparison: `activeAccountId` changed from the validation personal
  fixture account to the validation business fixture account.

The `seal run` output contained the expected runner layout:

- `proof/`
- `reports/result.json`
- `reports/report.md`
- `adapter/`

The direct and adapter-generated proof payloads matched for scenario,
feature, execution mode, invariant, event sequence, evidence paths, fixture
account snapshots, and verifier verdict. The only observed differences were
expected runtime fields: timestamps and run duration.

Current friction:

- CodexPill still needs a repo-local adapter because Seal must not know
  CodexPill scenario names, fixture setup, or proof emitter targets.
- The proof emitter still duplicates the account-switch Seal declaration shape
  because the current live validation declaration is embedded in menubar
  validation code and is restricted to `.liveUI`.
- The runner artifact layout is cleaner than the direct path: `seal run`
  produces `proof/`, `reports/result.json`, `reports/report.md`, and
  `adapter/` diagnostics under one root.
- The adapter invokes `make emit-account-switch-proof`, which means a full
  runner proof still performs CodexPill project generation and proof-emitter
  build work. That is acceptable for this deterministic boundary proof, but it
  is real orchestration cost rather than a lightweight contract check.

Decision after RGR-253: use `make verify-account-switch-seal` as the selected
account-switch runtime validation gate. Do not migrate all CodexPill validation
to `seal run` yet, and do not add CodexPill adapter discovery to Seal in this
slice.

## Add Host Validation Failure Seal Runner Boundary

RGR-254 extends the same compatibility-pointer pattern to
`add-host-destination-validation-failed`.

```bash
AGENT_NAME=symphony-RGR-254 make verify-add-host-validation-failure-seal
```

The CodexPill-owned adapter accepts the Seal runner contract explicitly and
routes the scenario to `make emit-add-host-validation-failure-proof`. The proof
is deterministic rather than live UI driven: it records validation start,
handled validation failure, before/after host catalog snapshots, and sanitized
domain feedback. Raw SSH output and sensitive host-specific material are not
included in proof diagnostics.

The wrapper keeps `codexpill-summary.json` as a compatibility pointer only.
Seal's `proof/`, `reports/result.json`, `reports/report.md`, and `adapter/`
artifacts are the authoritative runtime validation output. As with RGR-253, the
wrapper removes stale legacy runtime artifacts before invoking `seal run`, so
old CodexPill summaries or event logs cannot make the selected flow pass.

Pattern check after RGR-254: the RGR-253 compatibility-pointer approach scales
to this second flow without adding CodexPill business semantics to Seal. The
friction remains the explicit adapter ceremony and per-scenario wrapper naming;
that should feed a later Seal adapter-UX decision rather than be solved with
CodexPill-specific runner behavior.
