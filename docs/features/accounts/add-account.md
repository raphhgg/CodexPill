# Add Account

## User Story

As a CodexPill user, I want to add another Codex account without switching my current Codex account, so that I can prepare accounts for later use without disrupting my current local Codex work.

## Product Contract

- `Add Account` saves a new account; it does not switch the active local Codex account.
- `Use on This Mac` remains the explicit action that switches the active local account.
- Add Account captures the new sign-in through a temporary isolated `CODEX_HOME`.
- Temporary isolated auth state is treated as sensitive and must be cleaned up after success, cancellation, timeout, or failure.
- CodexPill must not log or expose raw auth payloads.

## Happy Path

1. The user chooses `Add Account...`.
2. CodexPill asks for the account display name.
3. CodexPill validates the display name before sign-in starts.
4. CodexPill starts an isolated Codex sign-in session.
5. CodexPill opens the Codex device-auth page in the browser.
6. CodexPill shows a sign-in alert with the device code and `Copy Code`.
7. The user completes sign-in in the browser.
8. CodexPill captures the isolated auth snapshot and verifies it.
9. CodexPill saves the account in the local catalog.
10. CodexPill confirms that the current local Codex account was not changed.
11. CodexPill shows a success alert with `Done` and `Use on This Mac`.

## Sign-In Alert

Title: `Sign in to Codex`

Body:

```text
CodexPill opened the Codex sign-in page in your browser.
Enter this code when prompted:
```

The code should be displayed prominently in a monospace style.

Actions:

- `Copy Code`: copies the code and keeps the alert open.
- `Cancel`: aborts the Add Account attempt.

Status:

```text
Waiting for browser sign-in...
```

## Success Alert

Title: `Account Added`

Body:

```text
"Business 7" was saved. Your current local Codex session was not changed.
```

Actions:

- `Use on This Mac`: routes through the existing local switch path for that saved account.
- `OK`: dismisses the alert.

Remote host actions are intentionally omitted from the v0 success alert. Users can switch the new account on a remote host from the normal account menu.

## Acceptance Criteria

### Unique Display Name

Given the user starts Add Account, when the user enters an empty or duplicate display name, then CodexPill blocks the flow before opening the browser or starting Codex sign-in.

### Device Code Visibility

Given CodexPill starts isolated sign-in, when Codex provides a device code, then CodexPill opens the browser and also displays the code in the app with a `Copy Code` action.

### Copy Code Keeps Waiting

Given the sign-in alert is visible, when the user selects `Copy Code`, then the code is copied and the alert remains open while CodexPill continues waiting for browser sign-in.

### Add Without Switching

Given the user completes browser sign-in, when CodexPill captures and saves the isolated account, then the saved account appears in the catalog and the live local Codex auth remains unchanged.

### Existing Switch Path

Given the success alert is visible, when the user selects `Use on This Mac`, then CodexPill routes through the existing local account switch confirmation and execution path.

### Cancel During Sign-In

Given isolated sign-in is in progress, when the user selects `Cancel`, then CodexPill terminates the isolated Codex login process, deletes the temporary `CODEX_HOME`, clears pending Add Account state, saves no account, and does not switch local auth.

### Duplicate Account Identity

Given the user completes browser sign-in with an account already saved under another display name, when CodexPill resolves the captured account identity, then CodexPill does not save a duplicate snapshot and shows:

Title: `Account Already Saved`

Body:

```text
This Codex account is already saved as "Business 4".
```

### Expired Code

Given isolated sign-in is waiting, when the device code expires before the account is added, then CodexPill clears pending state, cleans temporary auth state, and shows:

Title: `Sign-In Expired`

Body:

```text
The Codex sign-in code expired before the account was added.
```

Actions:

- `Cancel`
- `Try Again`

`Try Again` starts a fresh isolated login with a new temporary `CODEX_HOME` and a new code.

### Failed Before Code

Given Codex cannot start a device-auth session, when no device code is available, then CodexPill clears pending state, cleans temporary auth state, and shows:

Title: `Couldn't Start Sign-In`

Body:

```text
Codex could not start a sign-in session. Try again in a few minutes.
```

Action:

- `OK`

### Live Auth Mutation Guard

Given isolated Add Account starts, when CodexPill detects that live local auth changed during the flow, then CodexPill treats the attempt as unsafe, does not save the captured account, cleans temporary auth state, and shows:

Title: `Couldn't Add Account`

Body:

```text
CodexPill could not verify that your current account stayed unchanged. No account was added.
```

### Catalog Save Failure

Given isolated auth capture succeeds, when CodexPill cannot save the account to the catalog, then CodexPill cleans temporary auth state, does not switch local auth, and shows:

Title: `Couldn't Save Account`

Body:

```text
The sign-in completed, but CodexPill could not save the account. Your current Codex account was not changed.
```

### Quit During Sign-In

Given isolated sign-in is in progress, when CodexPill quits, then CodexPill aborts the isolated Codex login process and cleans temporary auth state.

### Crash Recovery Cleanup

Given CodexPill crashes during isolated sign-in, when CodexPill next launches, then it removes stale isolated Add Account temporary homes older than a safe threshold.

## Validation Targets

The Add Account acceptance criteria should drive unit, integration, and live UI validation. At minimum, validation should cover:

- `add_account_duplicate_display_name_blocks_before_sign_in`
- `add_account_shows_device_code_and_copy_action`
- `add_account_copy_code_keeps_waiting`
- `add_account_saves_without_switching`
- `add_account_use_on_this_mac_routes_existing_switch_flow`
- `add_account_cancel_cleans_up`
- `add_account_duplicate_identity_blocks_after_sign_in`
- `add_account_expired_code_allows_try_again`
- `add_account_failed_before_code_clears_state`
- `add_account_live_auth_mutation_aborts`
- `add_account_catalog_save_failure_does_not_switch`
- `add_account_quit_cleans_up`
- `add_account_startup_removes_stale_temp_homes`
