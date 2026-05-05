# Seal V1 Boundary Validation

This document records CodexPill's internal proof emitter for the Seal V1 adoption boundary.

The current V1 boundary is deliberately split:

- CodexPill owns a proof-producing entrypoint for a real product rule.
- Seal owns verification of the emitted proof through `seal-verifier`.

This slice validates `accounts.switch_account.menu_action_changes_active_account` without committing to the future `seal-run` product shape.

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

## Seal Run Adapter Prototype

CodexPill now has a prototype client-owned adapter for Seal's provisional
`seal run` command:

```bash
swift run --package-path /Users/raphh/Projects/Seal seal run \
  --scenario switch-account-changes-active-account \
  --output build/seal-run/account-switch \
  --proof-output build/seal-run/account-switch/proof \
  --adapter scripts/seal_run_adapter.sh
```

The adapter accepts Seal's generic `--scenario`, `--proof-output`, and
`--artifact-root` inputs, resolves the CodexPill-owned deterministic account
switch scenario, emits proof through `make emit-account-switch-proof`, and writes
CodexPill diagnostics under the runner-owned `adapter/` directory.

The direct baseline remains:

```bash
OUTPUT_DIR=build/validation-proof/account-switch make emit-account-switch-proof
swift run --package-path /Users/raphh/Projects/Seal seal-verifier \
  --result-json \
  --markdown-report \
  --output-dir build/validation-proof/account-switch-report \
  build/validation-proof/account-switch
```

Prototype decision: continue toward CodexPill `seal run` adoption for
deterministic Seal-backed scenarios, but keep direct `seal-verifier` as the
stable path until `seal run` is no longer provisional. The adapter boundary fits
the existing account-switch proof emitter cleanly without moving CodexPill
scenario resolution, fixture setup, or business semantics into Seal.

The first failure path exercised by this prototype is adapter-side scenario
resolution: unsupported scenarios exit non-zero and write diagnostics under
`adapter/`. Invalid-proof behavior remains owned by Seal's runner and verifier
tests for now because forcing this CodexPill adapter to emit malformed proof
would add test-only behavior to the product adapter.

## Runner/Orchestrator Friction

Current friction:

- CodexPill still needs a repo-local adapter because Seal must not know
  CodexPill scenario names, fixture setup, or proof emitter targets.
- The proof emitter still duplicates the account-switch Seal declaration shape
  because the current live validation declaration is embedded in menubar
  validation code and is restricted to `.liveUI`.
- The runner artifact layout is cleaner than the direct path: `seal run`
  produces `proof/`, `reports/result.json`, `reports/report.md`, and
  `adapter/` diagnostics under one root.
