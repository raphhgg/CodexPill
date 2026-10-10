# Switch Account

## User Story

As a CodexPill user, I want to switch a saved Codex account onto This Mac, so that I can continue working with an account that has available capacity.

## Product Contract

- Switching is always explicit. Adding, renaming, or removing an account must not implicitly switch the active account.
- `Switch on This Mac` activates the selected saved snapshot as the local Codex auth state.
- Local switching relaunches Codex so the app-server reads the newly active account.
- CodexPill must not log or expose raw auth payloads during switch operations.

## Entry Points

- Saved account submenu: `Switch on This Mac`.
- Add Account success alert: `Use on This Mac`, which routes through the existing local switch path without showing a second switch confirmation.

## Local Happy Path

1. The user opens a saved account submenu.
2. The user chooses `Switch on This Mac`.
3. CodexPill asks for confirmation.
4. CodexPill replaces the local Codex auth state with the saved snapshot.
5. CodexPill persists the catalog state.
6. CodexPill relaunches Codex.
7. CodexPill refreshes account data after the switch.

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

## Validation Targets

- `switch_account_local_confirms_before_activation`
- `switch_account_local_activates_snapshot_and_relaunches_codex`
- `switch_account_add_account_success_uses_existing_switch_path`
