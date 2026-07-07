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

Given a saved account is renamed, then the saved auth snapshot, Codex identity, active local auth state, and remote installed snapshots remain unchanged.

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

## Validation Scenario Candidates

- `rename-account-label-only`

## Validation Intent

Feature risk: `pure_model`, `state_truth`, `privacy`

Primary proof: `unit`

Product scenarios:

- `rename-account-label-only` proves that renaming changes only the display
  label, preserves saved auth snapshot, Codex identity, plan, and rate-limit
  data, rejects empty, whitespace-only, duplicate, and same-name inputs without
  auth mutation, and persists successful renames in display-name sort order.

Required evidence:

- focused test output from `RenameSavedAccountUseCaseTests`;
- Kite scenario receipt for `rename-account-label-only`.

Non-claims:

- Does not prove native rename dialog presentation or text entry.
- Does not prove live auth mutation or live Codex process state.
- Does not prove remote host mutation.
- Does not prove live macOS menu-bar behavior.

Live opt-in: not required for this scenario.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Rename changes only the display label. | `unit` | `make verify-rename-scenario` running `RenameSavedAccountUseCaseTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | The catalog display label updates while saved auth snapshot filename, Codex identity, plan, and rate-limit data remain unchanged, and no active-auth mutation boundary is involved. This unit scenario does not prove native menu row copy or dialog interaction. | Synthetic account labels and snapshots only; no raw auth, tokens, account identifiers, private paths, emails, or hostnames. |
| Empty or duplicate names are rejected. | `unit` | `make verify-rename-scenario` running `RenameSavedAccountUseCaseTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Empty/whitespace-only and case-insensitive duplicate names keep the original label and do not mutate catalog or auth state. | Synthetic labels only; no private account data. |
| Same-name rename is a no-op and successful rename preserves catalog ordering. | `unit` | `make verify-rename-scenario` running `RenameSavedAccountUseCaseTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Same-name confirmation does not create duplicates or change auth state; successful rename reorders the catalog according to display-name sort rules when persisted. | Synthetic labels only; no raw auth, tokens, emails, hostnames, or private paths. |
| Busy state blocks rename. | `deterministic-ui` plus `workflow-event-log` | Menu action availability test with fake busy workflow state. | Action-availability receipt plus optional menu projection assertion. | Rename action is disabled while another account operation is active and no rename workflow starts. | Synthetic state only; no raw workflow payloads, auth data, tokens, paths, emails, or hostnames. |

## Validation Targets

- `rename_account_updates_display_label`
- `rename_account_does_not_change_auth_snapshot_or_identity`
- `rename_account_rejects_empty_name`
- `rename_account_rejects_duplicate_name_case_insensitively`
- `rename_account_same_name_is_noop`
- `rename_account_sorts_catalog_by_display_name`
- `rename_account_disabled_while_busy`
