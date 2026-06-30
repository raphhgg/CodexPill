# Switch Account

## User Story

As a CodexPill user, I want to switch a saved Codex account onto This Mac or a configured remote host, so that I can continue working with an account that has available capacity.

## Product Contract

- Switching is always explicit. Adding, renaming, or removing an account must not implicitly switch the active account.
- `Switch on This Mac` activates the selected saved snapshot as the local Codex auth state.
- Remote switch actions target a specific configured host.
- If a saved account is not installed on a remote host, or the host has an older cached snapshot for that account, the remote action installs the current saved snapshot before switching.
- Local switching relaunches Codex so the app-server reads the newly active account.
- If the selected remote account is also the active local account, CodexPill refreshes and relinks the saved snapshot from the current local auth before installing or switching it on the host.
- If that active-account status refresh fails but live auth identity still uniquely matches the selected saved account, CodexPill still relinks the saved snapshot from current local auth before switching.
- Remote switching refreshes the remote Codex app-server after the remote auth change and verifies the expected account.
- CodexPill must not log or expose raw auth payloads during switch operations.

## Entry Points

- Saved account submenu: `Switch on This Mac`.
- Saved account submenu for each configured host:
  - `Switch on <host>` when the account is already installed on that host.
  - `Install on <host> and switch` when the account snapshot is missing on that host.
- Add Account success alert: `Use on This Mac`, which routes through the existing local switch path without showing a second switch confirmation.
- Account availability notifications: action buttons may route to the same local or remote switch paths.

## Local Happy Path

1. The user opens a saved account submenu.
2. The user chooses `Switch on This Mac`.
3. CodexPill asks for confirmation.
4. CodexPill replaces the local Codex auth state with the saved snapshot.
5. CodexPill persists the catalog state.
6. CodexPill relaunches Codex.
7. CodexPill refreshes account data after the switch.

## Remote Happy Path

1. The user opens a saved account submenu.
2. The user chooses a remote host switch action.
3. If the selected account is active on This Mac, CodexPill refreshes the saved snapshot from the current local auth.
4. CodexPill checks whether the account snapshot is already installed and fresh on that host.
5. If missing or stale, CodexPill installs the current saved snapshot on the host.
6. CodexPill switches the host to that account.
7. CodexPill refreshes the remote Codex app-server.
8. CodexPill verifies that the remote host reports the expected account.
9. CodexPill updates the remote host account state shown in the menu.

## Confirmation Copy

Local switch title:

```text
Switch account?
```

Local switch action:

```text
Switch
```

If Codex terminals are running, the confirmation warns that they must be restarted to use the new account.

## Acceptance Criteria

### Explicit Local Switch

Given a saved account exists, when the user chooses `Switch on This Mac`, then CodexPill asks for confirmation before activating the selected snapshot.

### Local Switch Relaunches Codex

Given the user confirms a local switch, when CodexPill activates the selected snapshot, then CodexPill relaunches Codex and refreshes account data after the switch.

### Add Account Uses Existing Switch Path

Given Add Account succeeds, when the user chooses `Use on This Mac`, then CodexPill switches through the existing local switch path and does not show a second switch confirmation.

### Remote Install And Switch

Given a saved account is not installed on a configured host, when the user chooses `Install on <host> and switch`, then CodexPill installs the account snapshot before switching the remote host.

### Remote Reinstalls Stale Cached Snapshot

Given a configured host has an older cached snapshot for the selected saved account, when the user switches that account on the host, then CodexPill treats the host snapshot as missing and reinstalls the current saved snapshot before switching.

### Remote Switch Refreshes Active Local Snapshot

Given the selected saved account is the active local account and local Codex auth was refreshed since the account was saved, when the user switches that account on a remote host, then CodexPill relinks the saved snapshot from current local auth before installing or switching it remotely.

If active-account status refresh fails, CodexPill may still relink from current local auth when live auth identity uniquely resolves to that saved account.

### Remote Direct Switch

Given a saved account is already installed on a configured host, when the user chooses `Switch on <host>`, then CodexPill switches the remote host without reinstalling the snapshot.

### Remote Verification

Given a remote switch completes, when CodexPill refreshes the remote Codex app-server, then it verifies that the reported remote account matches the selected saved account.

### Remote Verification Failure

Given a remote switch command completes but verification reports a different or ambiguous account, then CodexPill surfaces the verification failure instead of silently marking the remote switch as successful.

## Validation Scenario Candidates

- `switch-account-local-confirmed`
- `switch-account-remote-install-verify`

## Validation Intent

Feature risk: `auth_mutation`, `workflow_state`, `privacy`

Primary proof for `switch-account-local-confirmed`: `workflow-event-log`

Product scenarios:

- `switch-account-local-confirmed` proves that `Switch on This Mac` presents a
  confirmation before mutating local auth, cancellation leaves This Mac
  unchanged, confirmation activates the selected saved snapshot through fake
  auth/process clients, Codex relaunch is requested, Add Account success can
  reuse the same local switch path without a second confirmation, and
  post-switch refresh behavior is covered by the silent refresh proof.

Required evidence:

- focused test output from `SwitchAccountWorkflowTests`,
  `MenuBarRuntimeValidationTests`, `MenuBarAlertFactoryTests`,
  `MenuBarValidationObserverTests`, `AccountActionFlowTests`, and
  `SilentPostActionRefreshTests`;
- `build/verification/switch-account-local-confirmed/workflow-receipt.json`;
- `build/verification/switch-account-local-confirmed/scenario-summary.json`.

Non-claims:

- The local-confirmed scenario does not prove native confirmation panel
  rendering, click automation, live Codex process relaunch, live app-server
  refresh, remote host switching, or live macOS menu-bar behavior.
- `switch-account-remote-install-verify` remains a separate target scenario.

Live opt-in: not required for this scenario.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Local switch asks for confirmation before activating the saved snapshot. | `workflow-event-log` | `make verify-switch-account-local-confirmed-scenario` running `SwitchAccountWorkflowTests`, `MenuBarRuntimeValidationTests`, `MenuBarAlertFactoryTests`, `MenuBarValidationObserverTests`, `AccountActionFlowTests`, and `SilentPostActionRefreshTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/switch-account-local-confirmed/workflow-receipt.json`, and `scenario-summary.json`. | Auth activation is not called before confirmation; cancellation leaves This Mac auth unchanged and does not relaunch Codex; confirming writes the selected snapshot, persists catalog state, relaunches Codex through the fake process client, records switch workflow events, and the post-switch active-account refresh proof applies refreshed metadata when status data is available. | Fake auth snapshots, fake process clients, synthetic account ids, and synthetic status data only; receipts must not include raw auth JSON, tokens, private paths, emails, hostnames, or stable account identifiers. |
| Add Account success uses the existing switch path without a second confirmation. | `workflow-event-log` | Included in `make verify-switch-account-local-confirmed-scenario` through `AccountActionFlowTests`. | `build/results/local/CodexPill.xcresult` and scenario summary. | The success action resolves to the same local switch step with confirmation suppression, and no duplicate confirmation prompt is emitted by the action flow. | Synthetic account ids only; no raw auth, tokens, paths, emails, or hostnames. |
| Remote switch installs missing or stale snapshots before switching. | `workflow-event-log` plus `contract-fixture` | Remote switch test with `InMemoryRemoteHostClient` or fake SSH contract. | Structured remote-operation receipt. | Missing or stale host snapshots trigger install before switch; already-fresh snapshots use direct switch; operation order is visible in the receipt. | Fake remote hosts and snapshots only; no raw SSH output, auth payloads, tokens, private paths, real emails, or hostnames. |
| Remote switch refreshes and verifies the expected account. | `workflow-event-log` plus `integration` | Remote switch verification test with fake app-server/status clients. | Remote refresh and verification receipt. | After switching, CodexPill refreshes remote app-server state and marks success only when the reported account uniquely matches the selected saved account. | Synthetic app-server payloads only; no raw auth, tokens, emails, hostnames, private paths, or stable account identifiers. |
| Remote verification failure is surfaced instead of silently accepted. | `unit` plus `workflow-event-log` | Remote verification failure test with ambiguous and mismatched fixtures. | Failure-state receipt plus menu projection assertion when applicable. | Mismatch or ambiguity produces a recoverable failure state and does not present the host as verified active. | Synthetic fixtures only; no raw SSH output, auth payloads, tokens, emails, hostnames, or private paths. |

## Validation Targets

- `switch_account_local_confirms_before_activation`
- `switch_account_local_activates_snapshot_and_relaunches_codex`
- `switch_account_add_account_success_uses_existing_switch_path`
- `switch_account_remote_installs_missing_snapshot_before_switch`
- `switch_account_remote_reinstalls_stale_snapshot_before_switch`
- `switch_account_remote_relinks_active_local_snapshot_before_switch`
- `switch_account_remote_switches_directly_when_snapshot_exists`
- `switch_account_remote_verifies_expected_account`
- `switch_account_remote_surfaces_verification_failure`
