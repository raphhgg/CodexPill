# Remove Account

## User Story

As a CodexPill user, I want to remove a saved account from the local catalog, so that accounts I no longer want to use do not clutter the menu or get suggested.

## Product Contract

- Removing an account deletes CodexPill's saved local snapshot for that account.
- If the removed account is currently active locally, CodexPill signs out the local Codex auth and relaunches Codex before deleting the saved snapshot.
- If the removed account is currently active on a connected remote host, CodexPill signs out that remote host before deleting the saved snapshot.
- If any required sign-out fails, CodexPill keeps the saved account and reports the real failure.
- Removing an account does not delete remote snapshots already installed on remote hosts.
- The action is destructive for the local saved snapshot and must require confirmation.
- CodexPill must not log or expose raw auth payloads during removal.

## Entry Point

Saved account submenu:

```text
Remove…
```

## Happy Path

1. The user opens a saved account submenu.
2. The user chooses `Remove…`.
3. CodexPill shows a destructive confirmation.
4. The user confirms `Remove` or `Sign Out and Remove`.
5. CodexPill signs out any active local or connected remote target that is using the account.
6. CodexPill deletes the saved snapshot for that account.
7. CodexPill removes the account from the local catalog.
8. CodexPill recomputes the active saved-account match.

## Confirmation Copy

Title:

```text
Remove saved account?
```

Body:

```text
This removes <account> from CodexPill.

This action cannot be undone.
```

If the account is currently active locally or remotely, use:

Title:

```text
<account> is in use
```

Body:

```text
Sign out on <target list> before removing it?
```

Actions:

- `Remove`
- `Sign Out and Remove` when active targets must be signed out first
- `Cancel`

## Acceptance Criteria

### Confirmation Required

Given a saved account exists, when the user chooses `Remove…`, then CodexPill asks for confirmation before deleting the saved snapshot.

### Cancel Does Not Mutate

Given the remove confirmation is visible, when the user chooses `Cancel`, then CodexPill keeps the account, snapshot, active account match, and menu state unchanged.

### Remove Deletes Local Snapshot

Given the user confirms removal, then CodexPill deletes the saved local snapshot for that account and removes the account from the catalog.

### Active Account Removal Signs Out First

Given the removed account is the active local saved account, when removal completes, then the local Codex auth is signed out and Codex is relaunched before the saved snapshot is deleted.

### Remote Active Account Removal Signs Out First

Given the removed account is active on a connected remote host, when removal completes, then the remote host is signed out before the saved snapshot is deleted and the remote card no longer presents the removed account as active.

### Sign-Out Failure Does Not Remove

Given the removed account is active locally or remotely, when a required sign-out fails, then CodexPill keeps the saved snapshot and catalog row and shows the failure.

### Remote Snapshots Are Not Deleted

Given the removed account had previously been installed on a remote host but is not the active remote account, when the saved account is removed locally, then CodexPill does not delete remote files as part of this action.

### Busy State Blocks Removal

Given CodexPill is performing another account operation, then remove actions are disabled until the app returns to idle.

## Validation Scenario Candidates

- `remove-account-active-targets-sign-out`
- `remove-account-signout-failure-keeps-control`

## Validation Intent

Feature risk: `auth_mutation`, `workflow_state`, `failure_path`, `privacy`

Primary proof for `remove-account-active-targets-sign-out`: `workflow-event-log`

Primary proof for `remove-account-signout-failure-keeps-control`:
`workflow-event-log`

Product scenarios:

- `remove-account-active-targets-sign-out` proves that removing an active saved
  account presents destructive confirmation before mutation, signs out local
  auth and active remote hosts before deleting the saved snapshot, removes the
  account from the catalog, and no longer presents the removed account as active
  locally or remotely.
- `remove-account-signout-failure-keeps-control` proves that local and remote
  required sign-out failures stop removal before deleting the saved snapshot or
  catalog row, keep the active remote state pointed at the saved account, and
  surface the real sanitized failure to the user.

Required evidence:

- focused test output from `MenuBarRuntimeValidationTests`,
  `DeleteSavedAccountUseCaseTests`, and `MenuBarAlertFactoryTests`;
- Kite scenario receipt for `remove-account-active-targets-sign-out`.
- for sign-out failure, focused suite output from
  `MenuBarRuntimeValidationTests` and `DeleteSavedAccountUseCaseTests`;
- Kite scenario receipt for `remove-account-signout-failure-keeps-control`.

Non-claims:

- The active-target scenario does not prove native confirmation panel
  rendering, click automation, live Codex relaunch, live SSH sign-out, real
  remote auth mutation, required sign-out failure handling, or live macOS
  menu-bar behavior.
- The sign-out failure scenario does not prove native confirmation panel
  rendering, click automation, live Codex relaunch, live SSH sign-out, real
  remote auth mutation, remote inactive snapshot deletion, or live macOS
  menu-bar behavior.

Live opt-in: not required for this scenario.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Remove requires confirmation and cancel does not mutate state. | `workflow-event-log` | Remove coordinator test with fake confirmation presenter and catalog/auth stores. | Structured confirmation and mutation receipt. | No delete/sign-out call happens before confirmation; cancelling leaves catalog, saved snapshot, active account match, and menu state unchanged. | Synthetic account ids and snapshots only; no raw auth payloads, tokens, private paths, emails, hostnames, or prompts. |
| Removing an active account signs out local and remote active targets before deleting the saved snapshot. | `workflow-event-log` | `make verify-remove-account-active-targets-sign-out-scenario` running `MenuBarRuntimeValidationTests`, `DeleteSavedAccountUseCaseTests`, and `MenuBarAlertFactoryTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Required local and remote sign-outs happen before deleting the saved snapshot; local auth is removed and Codex relaunch is requested through the fake process client; after success the removed account is gone from the catalog and no longer presented as active locally or remotely. | Fake auth, fake process clients, fake remote fixtures, and synthetic snapshots only; no raw auth, tokens, raw SSH output, private paths, emails, or hostnames. |
| Required sign-out failure keeps the saved snapshot and catalog row. | `workflow-event-log` | `make verify-remove-account-signout-failure-keeps-control-scenario` running focused local and remote fake sign-out failure tests. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Failed local sign-out prevents snapshot deletion and catalog persistence; failed remote sign-out prevents saved-account deletion, keeps the catalog row, keeps remote desired and verified state pointed at the saved account, and surfaces the real sanitized failure. | Synthetic failure data, fake auth, fake remote host state, and synthetic snapshots only; no raw stderr, SSH output, auth payloads, tokens, private paths, emails, or hostnames. |
| Removing a locally saved account does not delete inactive remote snapshots. | `workflow-event-log` | Remove test with fake remote host containing inactive installed snapshot. | Remote-operation receipt. | The local saved snapshot is deleted after confirmation, and no remote file-delete operation is called for inactive remote snapshots. | Synthetic remote host and snapshot ids only; no raw SSH output, auth payloads, tokens, paths, emails, or hostnames. |

## Validation Targets

- `remove_account_requires_confirmation`
- `remove_account_cancel_does_not_mutate_catalog`
- `remove_account_deletes_local_snapshot_and_catalog_entry`
- `remove_account_active_local_session_signs_out_before_delete`
- `remove_account_active_remote_session_signs_out_before_delete`
- `remove_account_signout_failure_keeps_saved_account`
- `remove_account_does_not_delete_remote_snapshots`
- `remove_account_disabled_while_busy`
