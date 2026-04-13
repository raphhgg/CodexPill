# Human QA Plan

## Goal

Manually verify that `CodexPill` still behaves correctly after the recent architecture refactors and identify any user-visible bugs in account switching, refresh, sign-in, and menu behavior.

## Setup

1. Launch the app:

   ```bash
   ./scripts/run_menubar.sh
   ```

2. Keep `CodexPill` visible in the menu bar while testing.
3. Have at least two Codex accounts available if you want full switch-flow coverage.
4. If you want the same proof bundle the agent uses, run:

   ```bash
   make verify-ui
   make verify-ui-live
   ```

   The artifacts land in `build/verification/local/`.

## Test Cases

### 1. App Starts Cleanly

Steps:

1. Launch the app.
2. Open the menu bar popup.

Expected:

- the menu opens
- saved accounts are listed
- no permanent busy state is shown
- no stale error remains visible from startup

### 2. Save Current Account With Custom Name

Steps:

1. Choose the save-current-account action.
2. Enter a custom name.
3. Confirm the action.

Expected:

- the new account appears in the list
- it is sorted correctly
- it becomes or remains the active account
- no duplicate account appears

### 3. Save Current Account With Blank Name

Steps:

1. Choose the save-current-account action.
2. Leave the name blank or whitespace-only.
3. Confirm the action.

Expected:

- the app falls back to the current account email when available
- if no email exists, it falls back to a generic account name
- the save succeeds only once

### 4. Duplicate Name Is Rejected

Steps:

1. Try to save the current account using a name that already exists.

Expected:

- the save is rejected
- no account is overwritten or duplicated
- the app returns to a stable ready state

### 5. Switch To Another Saved Account

Steps:

1. Choose a different saved account.
2. Confirm the switch warning.

Expected:

- the warning mentions the target account
- Codex relaunches or reactivates through the app flow
- the selected account becomes active in `CodexPill`

### 6. Scheduled Refresh

Steps:

1. Note the currently displayed metadata for the active account.
2. Wait for the configured refresh interval to elapse.
3. Reopen the menu after the interval passes.

Expected:

- the scheduled refresh completes without a false app-server popup
- the active account remains the same logical account
- email, plan, and rate-limit information update if remote data changed
- the app returns to ready after the scheduled refresh

### 7. Sign In Another Account

Steps:

1. Start the sign-in-another flow.
2. Complete the Codex sign-in flow.
3. Reopen the menu.

Expected:

- the pending signed-in account is captured once
- the new account is saved without duplication
- it becomes the active account

### 8. Settings Affect The Menu Bar Correctly

Steps:

1. Open settings.
2. Change refresh interval.
3. Change visible inactive account count.
4. Change status bar indicator style.

Expected:

- the changes persist
- the menu reflects the new configuration
- the status item icon/appearance updates correctly

### 9. Busy And Error States Do Not Stick

Steps:

1. Trigger a save, switch, or refresh action.
2. If an error occurs, close and reopen the menu.

Expected:

- the busy state clears after the operation
- one error is shown once
- the app does not remain stuck in an unusable state

### 10. Reopen / Repeat Stability

Steps:

1. Open and close the menu multiple times.
2. Repeat a few core actions in sequence.

Expected:

- the menu keeps rebuilding correctly
- no duplicate rows or stale state appears
- the app remains responsive

## Out Of Scope

- Codex plugin marketplace or plugin-loader warnings by themselves
- unrelated Codex desktop network sync issues unless they block a `CodexPill` workflow

## What To Capture If Something Fails

Record:

- the exact action you took
- what you expected
- what actually happened
- whether the app recovered after reopening the menu
- whether the failure is repeatable
