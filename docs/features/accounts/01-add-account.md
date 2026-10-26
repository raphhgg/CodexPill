# Sign In To Another Codex Account

## User Story

As a rusage user, I want to sign in to another Codex account from rusage, so that I can use that account for Codex on this Mac without signing out and in again by hand.

## Product Contract

- rusage shows one Codex account. A new sign-in replaces it; rusage keeps no list of accounts.
- The browser sign-in runs in a temporary isolated `CODEX_HOME`. Nothing on this Mac changes until the user confirms.
- The finished sign-in is held in memory only. rusage never writes it anywhere but `~/.codex/auth.json`, and only after the user confirms.
- Temporary isolated auth state is treated as sensitive and must be cleaned up after success, cancellation, timeout, or failure.
- Only one sign-in may run at a time. A sign-in and a reset never overlap.
- The sign-in classifies isolated failures as account-domain outcomes before the menubar renders native alerts or retry panels.
- An account is identified by its email, masked with Hide Emails. Without an email it reads as its workspace, then its plan, then `Codex account`. Users never type a name.
- Whether the new sign-in is the account already in use is decided by account identity, never by label.
- rusage must not log or expose raw auth payloads.

## Entry Points

- `Settings › Accounts › Codex › Use Another Account…`
- `Sign In…` on that row when Codex is signed out.
- The first-run prompt below.

## Happy Path

1. The user chooses `Use Another Account…`.
2. rusage starts an isolated Codex sign-in session.
3. rusage shows a sign-in alert with the device code, `Copy Code`, and `Open Browser`.
4. The user copies the code and opens the Codex device-auth page from the alert.
5. The user completes sign-in in the browser.
6. rusage captures the isolated sign-in, verifies it, and removes the temporary `CODEX_HOME`.
7. rusage asks whether to use the new account on this Mac.
8. On `Use on This Mac`, rusage writes `auth.json` (mode 0600), relaunches the Codex app, and refreshes.

## First Run

With nothing connected, rusage asks once at launch:

Title: `Sign in to Codex?`

Body: `Sign in to Codex in your browser.`

Actions: `Not Now`, `Continue`. `Continue` starts the sign-in below.

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
- `Cancel`: aborts the sign-in.

Status:

```text
Waiting for browser sign-in...
```

## Confirmation

Title: `Use work@example.com for Codex?`

Body:

```text
work@example.com replaces personal@example.com on this Mac, and Codex restarts.
```

When Codex is signed out, the body reads `work@example.com becomes the Codex account on this Mac, and Codex restarts.` If Codex terminals are running, the body adds `2 Codex terminals are running. Restart to use the new account.`

Actions:

- `Use on This Mac`: writes `auth.json`, relaunches Codex, and refreshes.
- `Cancel`: drops the sign-in. This Mac is unchanged.

## Acceptance Criteria

### Device Code Visibility

Given rusage starts isolated sign-in, when Codex provides a device code, then rusage displays the code in the app with `Copy Code` and `Open Browser` actions before opening the browser.

### Copy Code Keeps Waiting

Given the sign-in alert is visible, when the user selects `Copy Code`, then the code is copied and the alert remains open while rusage continues waiting for browser sign-in.

### Nothing Changes Before Confirmation

Given the user completes browser sign-in, when the confirmation is visible or the user chooses `Cancel`, then `auth.json` is unchanged and the sign-in exists only in memory.

### Use On This Mac

Given the confirmation is visible, when the user chooses `Use on This Mac`, then rusage replaces `auth.json` with the new sign-in, relaunches Codex, and refreshes the account's limits.

### Overlapping Sign-In

Given a sign-in is already waiting for the browser, when the user or runtime attempts to start another, then rusage rejects the second attempt without cancelling or clearing the first.

### Cancel During Sign-In

Given isolated sign-in is in progress, when the user selects `Cancel`, then rusage terminates the isolated Codex login process, deletes the temporary `CODEX_HOME`, and does not change `auth.json`.

### Account Already In Use

Given the user completes browser sign-in with the account already in use, then rusage changes nothing and shows:

Title: `Already Signed In`

Body:

```text
This Codex account is already the one on this Mac.
```

### Live Auth Mutation Guard

Given a sign-in is running, when `auth.json` changes before it finishes, then rusage drops the new sign-in so it cannot overwrite a sign-in made elsewhere, and shows:

Title: `Couldn't Sign In`

Body:

```text
The Codex sign-in on this Mac changed meanwhile. Nothing was replaced.
```

### Expired Code

Given isolated sign-in is waiting, when the device code expires before sign-in finishes, then rusage cleans temporary auth state and shows:

Title: `Sign-In Expired`

Body:

```text
The Codex sign-in code expired before you finished signing in.

If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.
```

Actions:

- `Cancel`
- `Try Again`

`Try Again` starts a fresh isolated login with a new temporary `CODEX_HOME` and a new code.

### Failed Before Code

Given Codex cannot start a device-auth session, when no device code is available, then rusage cleans temporary auth state and shows:

Title: `Couldn't Start Sign-In`

Body:

```text
Codex could not start a sign-in session. Check your network connection, then try again.

If ChatGPT asked you to enable device-code authorization, enable it in ChatGPT Security Settings, then try again.
```

Action:

- `OK`

If Codex provides a startup error before the device code is available, rusage may append a sanitized `Codex reported: ...` diagnostic. Device codes and auth URL query strings must be redacted before any diagnostic is shown.

### Codex App Not Found

Sign-in runs the Codex CLI that the Codex app ships (`Contents/Resources/codex-cli/bin/codex` in ChatGPT.app, `Contents/Resources/codex` in earlier Codex.app builds). rusage finds the app by bundle ID, so its name does not matter.

- Given no Codex app is found, when the user starts a sign-in, then rusage shows `Codex app not found` / `Install the Codex app, then sign in again.`
- Given the Codex app is gone when the user confirms, then rusage still writes `auth.json`, skips the relaunch, and shows `Codex app not found` / `Signed in. Codex uses the account when it opens.`

### Quit During Sign-In

Given isolated sign-in is in progress, when rusage quits, then rusage aborts the isolated Codex login process and cleans temporary auth state.

### Crash Recovery Cleanup

Given rusage crashes during isolated sign-in, when rusage next launches, then it removes stale isolated temporary homes older than a day.

## Validation Targets

`Tests/Accounts/AccountsControllerTests.swift` and `Tests/Accounts/AccountActionFlowTests.swift` cover:

- a new sign-in replaces `auth.json` only when used, and relaunches Codex;
- signing in to the account already in use changes nothing;
- a sign-in made elsewhere during the browser sign-in is never overwritten;
- a second sign-in is refused while one runs, and a reset is refused while a sign-in runs;
- each failure maps to its own alert step: expired code offers a retry, a missing Codex app gets its own alert, and cancellation shows no error.
