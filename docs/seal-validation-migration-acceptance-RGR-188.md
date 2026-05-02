# Seal Validation Migration Acceptance - RGR-188

Date: 2026-05-02

## Decision

CodexPill can rely on Seal as the canonical validation gate for its current Seal-backed live validation flows, with one report-format caveat: `seal-verifier` currently exposes pass/fail evidence through stdout/stderr logs, not a standalone verifier `result.json`.

This checkpoint is acceptable for Seal Phase 8 release readiness as long as the missing machine-readable verifier result is tracked as a follow-up and not treated as a CodexPill release blocker.

## Fresh Matrix Evidence

Fresh artifact root:

`build/verification/symphony-RGR-188-final-20260502203315`

Seal-backed scenarios verified with `seal_swift_run`:

| Scenario | Seal scenario | Proof sequence |
| --- | --- | --- |
| `live-add-account-name-dialog-cancelled` | `add-account-name-dialog-cancelled` | `menu_action_dispatched -> add_account_name_dialog_presented -> add_account_name_dialog_cancelled` |
| `live-account-switch` | `switch-account-changes-active-account` | `menu_action_dispatched -> switch_confirmation_presented -> switch_confirmation_accepted -> switch_workflow_started -> active_account_changed` |
| `live-add-host-destination-validation-failed` | `add-host-destination-validation-failed` | `menu_action_dispatched -> add_host_setup_presented -> add_host_validation_started -> add_host_validation_failed` |
| `live-remote-host-switch` | `switch-account-on-host-changes-remote-active-account` | `menu_action_dispatched -> remote_host_switch_started -> remote_host_active_account_changed` |
| `live-scheduled-refresh` | `scheduled-refresh-preserves-account-catalog` | `scheduled_refresh_requested -> scheduled_refresh_completed` |

Each listed scenario has:

- `summary.json` status `passed`
- `sealProofVerificationMode` set to `seal_swift_run`
- empty `gaps`
- `seal-proof/manifest.json`
- `seal-proof/evidence/events.jsonl`
- scenario-specific snapshot evidence where required by the Seal manifest
- `logs/seal-verifier.stdout.log` containing `SealVerifier: passed`

The validation scripts now fail these scenarios when Seal verification fails. Passing validation no longer depends only on legacy proof summaries, manifest existence, or stale artifact presence.

## Flow Inventory

Migrated to Seal-backed canonical validation:

- `live-add-account-name-dialog-cancelled`
- `live-account-switch`
- `live-add-host-destination-validation-failed`
- `live-remote-host-switch`
- `live-scheduled-refresh`

Intentionally legacy or out of Seal scope:

- Unit and integration tests for pure domain, persistence, auth parsing, app-server parsing, switching orchestration, SSH command mapping, and menu projection rules.
- Deterministic hosted UI validation scenarios, where the canonical evidence is static menu rendering and JSON snapshot shape rather than a live event proof.
- `live-menu-open` and `live-status-item-hover`, which prove runtime menu availability, menu row layout, action wiring, and status-item hover behavior without a Seal scenario contract.

Follow-up migration candidates:

- [RGR-190](https://linear.app/raphh/issue/RGR-190/emit-machine-readable-seal-verifier-result-artifact-for-codexpill): add a machine-readable verifier result artifact for each Seal-backed run, preferably `logs/seal-verifier.result.json` or `seal-proof/result.json`.
- Consider whether `live-menu-open` should gain a Seal scenario if CodexPill wants a canonical Seal proof for baseline menubar runtime availability.

## Implementation Review Notes

Feature and scenario declarations are scoped by feature (`accounts` or `hosts`) and use stable scenario aliases from the existing live validation names. All Seal scenarios declare `.liveUI` execution mode.

Evidence IDs and proof paths are stable and human-inspectable:

- event streams: `evidence/events.jsonl`
- account snapshots: `evidence/account-before.json`, `evidence/account-after.json`
- Add Account dialog snapshot: `evidence/name-dialog-snapshot.json`
- Add Host validation snapshot: `evidence/host-validation-snapshot.json`
- scheduled refresh UI snapshot: `evidence/ui-after-refresh.json`

Generic Seal rules are used directly for event sequence, event existence, snapshot equality, snapshot difference, and snapshot value equality. Recorder setup starts one Seal run per mapped live scenario and cancels unfinished runs during observer teardown.

The live harness removes each scenario proof directory before execution and writes every run under a unique `ARTIFACT_ROOT`, which resists stale proof reuse. Seal setup, missing manifest, verifier unavailability, and verifier rejection now produce failed summaries with `failureStep: seal_proof_verification`.

## Caveats

The current `seal-verifier` log output is acceptable for this release checkpoint, but it is weaker than a structured `result.json` for downstream automation. [RGR-190](https://linear.app/raphh/issue/RGR-190/emit-machine-readable-seal-verifier-result-artifact-for-codexpill) tracks that Seal/reporting contract improvement; it is not a CodexPill migration blocker.
