# Switch Account

## User Story

As a rusage user, I want to switch a saved Codex account onto This Mac, so that I can continue working with an account that has available capacity.

## Product Contract

- Switching is always explicit. Adding, renaming, or removing an account must not implicitly switch the active account.
- `Switch on This Mac` activates the selected saved snapshot as the local Codex auth state.
- Local switching relaunches Codex so the app-server reads the newly active account.
- rusage must not log or expose raw auth payloads during switch operations.

## Entry Points

- Saved account submenu: `Switch on This Mac`.
- Add Account success alert: `Use on This Mac`, which routes through the existing local switch path without showing a second switch confirmation.

## Local Happy Path

1. The user opens a saved account submenu.
2. The user chooses `Switch on This Mac`.
3. rusage asks for confirmation.
4. rusage replaces the local Codex auth state with the saved snapshot.
5. rusage persists the catalog state.
6. rusage relaunches Codex.
7. rusage refreshes account data after the switch.

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

Given a saved account exists, when the user chooses `Switch on This Mac`, then rusage asks for confirmation before activating the selected snapshot.

### Local Switch Relaunches Codex

Given the user confirms a local switch, when rusage activates the selected snapshot, then rusage relaunches Codex and refreshes account data after the switch.

### Switch Without The Codex App

Given the Codex app (`com.openai.codex`, which may be named ChatGPT.app) is not found, when the user confirms a local switch, then rusage still switches `auth.json`, skips the relaunch and shows `Codex app not found` / `Switched. Codex uses the account when it opens.`

### Add Account Uses Existing Switch Path

Given Add Account succeeds, when the user chooses `Use on This Mac`, then rusage switches through the existing local switch path and does not show a second switch confirmation.

## Validation Targets

- `switch_account_local_confirms_before_activation`
- `switch_account_local_activates_snapshot_and_relaunches_codex`
- `switch_account_add_account_success_uses_existing_switch_path`
