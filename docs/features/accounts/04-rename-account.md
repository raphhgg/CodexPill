# Rename Account

## User Story

As a CodexPill user, I want to rename a saved account, so that the account label matches how I think about using it without changing the underlying Codex identity.

## Product Contract

- Rename changes only the CodexPill display label.
- Rename does not mutate the saved auth snapshot.
- Rename does not switch the active local Codex account.
- Rename does not change the underlying Codex account identity, email, plan, or rate-limit data.
- Account names must be non-empty.
- Account names must be unique case-insensitively.
- Renaming to the same name with only casing-equivalent differences is allowed as a no-op.

## Entry Point

Saved account submenu:

```text
Rename…
```

## Happy Path

1. The user opens a saved account submenu.
2. The user chooses `Rename…`.
3. CodexPill asks for the new account name.
4. The user enters a unique non-empty label.
5. CodexPill updates the catalog entry.
6. CodexPill keeps the auth snapshot and active account state unchanged.
7. CodexPill sorts the account catalog by display name.

## Dialog Copy

Title:

```text
Rename saved account
```

Body:

```text
This only changes the name shown in CodexPill.
```

Field:

```text
Account Name
```

Actions:

- `Rename`
- `Cancel`

## Acceptance Criteria

### Rename Updates Display Label

Given a saved account exists, when the user enters a unique new name and confirms, then CodexPill updates that account's display label in the catalog and menu.

### Rename Does Not Change Auth

Given a saved account is renamed, then the saved auth snapshot, Codex identity, and active local auth state remain unchanged.

### Empty Name Rejected

Given the rename dialog is visible, when the user enters an empty or whitespace-only name, then CodexPill rejects the rename and keeps the original account name.

### Duplicate Name Rejected

Given another saved account already has the requested name case-insensitively, when the user confirms rename, then CodexPill rejects the rename and keeps the original account name.

### Same Name No-Op

Given the user confirms the existing account name, when CodexPill processes the rename, then it preserves the account catalog without creating a duplicate or changing auth state.

### Catalog Sorting

Given rename succeeds, when the account catalog is reloaded or rendered, then accounts appear in display-name sort order.

### Busy State Blocks Rename

Given CodexPill is performing another account operation, then rename actions are disabled until the app returns to idle.

## Validation Targets

- `rename_account_updates_display_label`
- `rename_account_does_not_change_auth_snapshot_or_identity`
- `rename_account_rejects_empty_name`
- `rename_account_rejects_duplicate_name_case_insensitively`
- `rename_account_same_name_is_noop`
- `rename_account_sorts_catalog_by_display_name`
- `rename_account_disabled_while_busy`
