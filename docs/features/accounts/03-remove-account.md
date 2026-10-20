# Remove Account

## User Story

As a rusage user, I want to remove a saved account from the local catalog, so that accounts I no longer want to use do not clutter the menu or get suggested.

## Product Contract

- Removing an account deletes rusage's saved local snapshot for that account.
- If the removed account is currently active locally, rusage signs out the local Codex auth and relaunches Codex before deleting the saved snapshot.
- If the sign-out fails, rusage keeps the saved account and reports the real failure.
- The action is destructive for the local saved snapshot and must require confirmation.
- rusage must not log or expose raw auth payloads during removal.

## Entry Point

Saved account submenu:

```text
Remove…
```

## Happy Path

1. The user opens a saved account submenu.
2. The user chooses `Remove…`.
3. rusage shows a destructive confirmation.
4. The user confirms `Remove` or `Sign Out and Remove`.
5. If the account is active on This Mac, rusage signs it out.
6. rusage deletes the saved snapshot for that account.
7. rusage removes the account from the local catalog.
8. rusage recomputes the active saved-account match.

## Confirmation Copy

Title:

```text
Remove saved account?
```

Body:

```text
This removes <account> from rusage.

This action cannot be undone.
```

If the account is currently active on This Mac, use:

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

Given a saved account exists, when the user chooses `Remove…`, then rusage asks for confirmation before deleting the saved snapshot.

### Cancel Does Not Mutate

Given the remove confirmation is visible, when the user chooses `Cancel`, then rusage keeps the account, snapshot, active account match, and menu state unchanged.

### Remove Deletes Local Snapshot

Given the user confirms removal, then rusage deletes the saved local snapshot for that account and removes the account from the catalog.

### Active Account Removal Signs Out First

Given the removed account is the active local saved account, when removal completes, then the local Codex auth is signed out and Codex is relaunched before the saved snapshot is deleted.

### Sign-Out Failure Does Not Remove

Given the removed account is active locally, when the sign-out fails, then rusage keeps the saved snapshot and catalog row and shows the failure.

### Busy State Blocks Removal

Given rusage is performing another account operation, then remove actions are disabled until the app returns to idle.

## Validation Targets

- `remove_account_requires_confirmation`
- `remove_account_cancel_does_not_mutate_catalog`
- `remove_account_deletes_local_snapshot_and_catalog_entry`
- `remove_account_active_local_session_signs_out_before_delete`
- `remove_account_signout_failure_keeps_saved_account`
- `remove_account_disabled_while_busy`
