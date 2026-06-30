# Add Account

## User Story

As a CodexPill user, I want to add another Codex account without changing This Mac, so that I can prepare accounts for later use without disrupting current Codex work.

## Product Contract

- `Add Account` saves a new account; it does not switch This Mac.
- `Use on This Mac` remains the explicit action that switches the active local account.
- Add Account captures the new sign-in through a temporary isolated `CODEX_HOME`.
- Temporary isolated auth state is treated as sensitive and must be cleaned up after success, cancellation, timeout, or failure.
- Only one Add Account sign-in may run at a time.
- Add Account classifies isolated sign-in failures as account-domain outcomes before the menubar renders native alerts or retry panels.
- After the account is saved, CodexPill attempts a best-effort isolated status read so the new account can show available session or weekly usage immediately. Returned windows are classified by duration instead of App Server `primary` / `secondary` field position.
- CodexPill must not log or expose raw auth payloads.

## Happy Path

1. The user chooses `Add Account…`.
2. CodexPill asks for the account display name.
3. CodexPill validates the display name before sign-in starts.
4. CodexPill starts an isolated Codex sign-in session.
5. CodexPill shows a sign-in alert with the device code, `Copy Code`, and `Open Browser`.
6. The user copies the code and opens the Codex device-auth page from the alert.
7. The user completes sign-in in the browser.
8. CodexPill captures the isolated auth snapshot and verifies it.
9. CodexPill saves the account in the local catalog.
10. CodexPill attempts to hydrate the saved account metadata and rate limits without switching local auth.
11. CodexPill confirms that This Mac was not changed.
12. CodexPill shows a success alert with `Done` and `Use on This Mac`.

## Name Prompt

Title: `Add account`

Body:

```text
Choose a name for this saved account. You can change it later.
```

Field:

- Label: `Account Name`
- Placeholder: `Work`
- `Continue` is disabled until the user enters a non-empty name.

If a defensive validation error still occurs, CodexPill should keep the user in
the Add Account name flow instead of ending on a separate generic error alert.

## Sign-In Alert

Title: `Sign in to Codex`

Body:

```text
Copy this code, then open the Codex sign-in page in your browser.
```

The code should be displayed prominently in a monospace style.

Actions:

- `Copy Code`: copies the code and keeps the alert open.
- `Open Browser`: opens the Codex sign-in page and keeps the alert open.
- `Cancel`: aborts the Add Account attempt.

Status:

```text
Waiting for browser sign-in...
```

## Success Alert

Title: `Account Added`

Body:

```text
"Business 7" was saved. This Mac was not changed.
```

Actions:

- `Use on This Mac`: switches to that saved account immediately without showing a second switch confirmation.
- `Done`: dismisses the alert.

If Codex terminals are running, the success alert should include the same restart warning used by normal local switch confirmations before the user chooses `Use on This Mac`.

Remote host actions are intentionally omitted from the v0 success alert. Users can switch the new account on a remote host from the normal account menu.

## Acceptance Criteria

### Unique Display Name

Given the user starts Add Account, when the user enters an empty or duplicate display name, then CodexPill blocks the flow before opening the browser or starting Codex sign-in.

### Device Code Visibility

Given CodexPill starts isolated sign-in, when Codex provides a device code, then CodexPill displays the code in the app with `Copy Code` and `Open Browser` actions before opening the browser.

### Copy Code Keeps Waiting

Given the sign-in alert is visible, when the user selects `Copy Code`, then the code is copied and the alert remains open while CodexPill continues waiting for browser sign-in.

### Add Without Switching

Given the user completes browser sign-in, when CodexPill captures and saves the isolated account, then the saved account appears in the catalog and the live local Codex auth remains unchanged.

### Post-Add Usage Hydration

Given Add Account saves a new inactive account, when CodexPill can read that account's status through the isolated app-server path, then CodexPill updates the saved account with returned email, plan, and any usable rate-limit window before leaving the Add Account flow.

If Codex returns only session or only weekly usage, CodexPill must preserve the returned usable window instead of treating the whole status as missing. For example, a Free account may return a weekly-length window as `primary`; CodexPill must show that as weekly usage, not session usage.

If hydration fails, Add Account still succeeds and the account remains saved; CodexPill may show missing usage until a later refresh succeeds.

### Overlapping Sign-In

Given Add Account is already waiting for browser sign-in, when the user or runtime attempts to start another Add Account flow, then CodexPill rejects the second attempt without cancelling or clearing the first pending sign-in.

### Use On This Mac

Given the success alert is visible, when the user selects `Use on This Mac`, then CodexPill switches to the saved account directly and does not show a second switch confirmation.

Given one or more Codex terminals are running, when the success alert is visible, then the alert warns that they must be restarted to use the new account.

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

If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.
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
Codex could not start a sign-in session. Check your network connection, then try again.

If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.
```

Action:

- `OK`

If Codex provides a startup error before the device code is available, CodexPill may append a sanitized `Codex reported: ...` diagnostic. Device codes and auth URL query strings must be redacted before any diagnostic is shown.

### Live Auth Mutation Guard

Given isolated Add Account starts, when CodexPill detects that live local auth changed during the flow, then CodexPill treats the attempt as unsafe, does not save the captured account, cleans temporary auth state, and shows:

Title: `Couldn't Add Account`

Body:

```text
CodexPill could not verify that This Mac stayed unchanged. No account was added.
```

### Catalog Save Failure

Given isolated auth capture succeeds, when CodexPill cannot save the account to the catalog, then CodexPill cleans temporary auth state, does not switch local auth, and shows:

Title: `Couldn't Save Account`

Body:

```text
The sign-in completed, but CodexPill could not save the account. This Mac was not changed.
```

### Quit During Sign-In

Given isolated sign-in is in progress, when CodexPill quits, then CodexPill aborts the isolated Codex login process and cleans temporary auth state.

### Crash Recovery Cleanup

Given CodexPill crashes during isolated sign-in, when CodexPill next launches, then it removes stale isolated Add Account temporary homes older than a safe threshold.

## Validation Scenario Candidates

- `add-account-name-validation`
- `add-account-isolated-success`
- `add-account-failure-cleanup`

## Validation Intent

Feature risk: `workflow_state`, `auth_isolation`, `privacy`

Primary proof for `add-account-name-validation`: `unit`

Primary proof for `add-account-isolated-success`: `workflow-event-log`

Product scenarios:

- `add-account-name-validation` proves that empty, whitespace-only, and
  case-insensitive duplicate display names are rejected before CodexPill starts
  isolated sign-in, and that display-name failures route back into the Add
  Account name-recovery flow.
- `add-account-isolated-success` proves that fake-client isolated Add Account
  saves the captured account as inactive, preserves the active This Mac account,
  hydrates the new inactive account through the fake saved-account status
  client when usable status is available, and cleans the isolated login session
  after success.

Required evidence:

- focused test output from `AddAccountWorkflowTests` and
  `AccountActionFlowTests`;
- `build/verification/add-account-name-validation/scenario-summary.json`.
- focused test output from `AddAccountWorkflowTests`, `AccountsControllerTests`,
  and `AccountActionFlowTests`;
- `build/verification/add-account-isolated-success/workflow-receipt.json`;
- `build/verification/add-account-isolated-success/scenario-summary.json`.

Non-claims:

- The name-validation scenario does not prove native Add Account panel
  rendering, text entry, or disabled `Continue` state.
- The isolated-success scenario does not prove native device-code panel
  rendering, browser sign-in, live Codex auth, live app-server, real process
  relaunch, or terminal failure cleanup paths.
- Neither scenario proves live macOS menu-bar behavior.

Live opt-in: not required for this scenario.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Empty or duplicate display names are blocked before sign-in starts. | `unit` | `make verify-add-account-name-scenario` running `AddAccountWorkflowTests` and `AccountActionFlowTests`. | `build/results/local/CodexPill.xcresult` and `build/verification/add-account-name-validation/scenario-summary.json`. | Empty, whitespace-only, and case-insensitive duplicate names throw before isolated login starts, keep the user in the Add Account name-recovery flow, and do not start browser/device-code sign-in. This unit scenario does not prove native panel rendering or the disabled `Continue` state. | Synthetic account names only; no raw auth payloads, tokens, account identifiers, private paths, emails, hostnames, or device codes. |
| Add Account saves an isolated account without switching This Mac. | `workflow-event-log` | `make verify-add-account-isolated-success-scenario` running `AddAccountWorkflowTests`, `AccountsControllerTests`, and `AccountActionFlowTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/add-account-isolated-success/workflow-receipt.json`, and `scenario-summary.json`. | The saved account appears in the catalog, live local auth is unchanged, saved-account hydration applies returned usable email, plan, and rate-limit metadata when available, the isolated login session is cleaned after success, and no Codex relaunch/switch occurs unless the success alert action is chosen. | Fake auth snapshots and fake status clients only; receipts must redact device codes, auth URLs, auth JSON, tokens, emails, account identifiers, private paths, and hostnames. |
| Terminal Add Account failures clean sensitive temporary state. | `integration` plus negative filesystem/state assertions | Add Account failure matrix tests for cancel, expiry, startup failure, live-auth mutation, save failure, quit, and stale temp-home cleanup. | Test result plus cleanup receipt. | Each terminal failure clears pending state, deletes temporary isolated homes when appropriate, saves no unintended account, and leaves live local auth unchanged. | Temporary fixture paths must be synthetic or redacted; no raw auth payloads, device codes, auth URLs, tokens, emails, account identifiers, or hostnames may appear in artifacts. |
| `Use on This Mac` routes through the existing switch flow without a second confirmation. | `workflow-event-log` | Add Account success action test with fake switch coordinator. | Structured action routing receipt. | Selecting `Use on This Mac` calls the existing local switch path once with confirmation suppression and does not duplicate switch prompts. | Synthetic account ids only; no raw auth payloads, tokens, private paths, emails, or hostnames. |

## Validation Targets

The Add Account acceptance criteria should drive unit, integration, and live UI validation. At minimum, validation should cover:

- `add_account_duplicate_display_name_blocks_before_sign_in`
- `add_account_shows_device_code_and_copy_action`
- `add_account_copy_code_keeps_waiting`
- `add_account_saves_without_switching`
- `add_account_hydrates_saved_account_usage_after_save`
- `add_account_rejects_overlapping_sign_in_without_clearing_pending_flow`
- `add_account_use_on_this_mac_routes_existing_switch_flow`
- `add_account_cancel_cleans_up`
- `add_account_duplicate_identity_blocks_after_sign_in`
- `add_account_expired_code_allows_try_again`
- `add_account_failed_before_code_clears_state`
- `add_account_live_auth_mutation_aborts`
- `add_account_catalog_save_failure_does_not_switch`
- `add_account_quit_cleans_up`
- `add_account_startup_removes_stale_temp_homes`
