# Claude Usage

## User Story

As a Refill user who also works in Claude Code on a Pro or Max plan, I want to see my Claude 5-hour and weekly limits next to my Codex limits, so I can pick the tool with headroom without opening Claude Code's `/usage` screen.

## Product Contract

Claude Usage is an optional menu bar feature. When connected, Refill shows the 5-hour and weekly limits of the Claude account that Claude Code is signed in to, and the last limits of every other Claude account the user saved.

Claude accounts work like Codex accounts, described in [Claude Accounts](#claude-accounts). Adding one runs Claude Code's own login in a throwaway config folder. Switching changes Claude Code's live sign-in, and with it whose limits the card shows. Reading usage never changes anything in Claude Code. Refill never renews a sign-in itself and never calls Anthropic's token endpoint: Claude Code does the renewing, of its own expired sign-in when it isn't running, and of a saved account's expired copy in a throwaway folder.

The feature is off by default. Connecting it is the user's consent for Refill to read Claude Code's sign-in and send it to Anthropic.

Claude usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

Refill never reads or writes Claude Code's `settings.json`. Reading limits from Anthropic, rather than from Claude Code's status line, means usage stays current when Claude Code runs in the Claude desktop app or remotely.

## Menu

The `Claude` card follows the shared card and side menu in [Menubar](menubar.md). The side menu marks the account in use, lists the other saved accounts with their last limits, and adds accounts. `Disconnect Claude` is in Settings.

- **Not connected.** There is no card. `Settings › Add Account › Claude…` (and the first-run `Add Account ›`) connects. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Claude Code?**
  > Uses Claude Code's sign-in to read your limits.

  Confirming saves the choice and reads at once. That first read may show the macOS Keychain prompt.
- **Connected.** The choice is saved in user defaults (`claudeUsageEnabled`, off by default). `Disconnect Claude` in Settings turns the feature off at once with no alert, because it changes nothing outside Refill.
- **Current.** The plan tag (`Max x20`, read from `organizationRateLimitTier`, else `userRateLimitTier`, in Claude Code's `oauthAccount`, because the credentials' `rateLimitTier` keeps the tier from sign-in time; that one is used only when the account record has none), then `Session` and `Weekly` meters with their reset times, then one meter per model with its own weekly limit, such as `Fable this week`, unless `Settings › Appearance › Show Model Limits` is off. There is no reset-credit row. The meters use the same percent mode, layout, colors, and pacing markers as the Codex card.
- **Waiting.** `Waiting for Claude Code usage`, with no second line. Anthropic answered but sent neither window, for example on a plan without subscription limits.
- **Keychain access needed.** The card says `Allow Keychain access` and one row under it, `Allow Keychain access…`, It reads again with the macOS Keychain prompt allowed. Claude Code rewrites its Keychain item when it renews its sign-in, which can reset an earlier `Always Allow`, so this state can come back.
- **Failures.** Each failure shows a title and one short line. Except for signed out, the last good values stay dimmed below it with their `As of` time.

  | Cause | Title | Second line |
  |---|---|---|
  | No sign-in | `Not signed in to Claude Code` | `Sign in to Claude Code to see usage.` |
  | Token past its expiry, or `401` | `Claude Code sign-in expired` | `Run claude to renew it.` |
  | Credentials file or Keychain item unreadable or not JSON | `Can't read the Claude Code sign-in` | `Sign in to Claude Code again.` |
  | `403` | `Anthropic won't share usage` | `Sign in to Claude Code again.` |
  | `429`, or waiting out `Retry-After` | `Anthropic asked to wait` | `Retrying in a few minutes.` |
  | No answer (offline, DNS, TLS, timeout) | `Can't reach Anthropic` | `Retrying in a few minutes.` |
  | Any other status | `Anthropic is having trouble` | `Retrying in a few minutes.` |
  | A `200` that is not the usage shape | `Unexpected reply from Anthropic` | `Retrying in a few minutes.` |
- **Stale.** A snapshot older than 15 minutes is dimmed. Its label still reads `As of …` until the next read.
- **Accounts.** The account in use is the first side-menu row, checked and disabled. Each other saved account is a row by email that opens `Use` and `Remove…`, with its last limits on a second line, for example `Session 12% · Weekly 40% used`. A reading older than 30 minutes adds `· as of 10:26`. An account read once shows nothing more.
- **`Add Claude Account…`** runs Claude Code's login in the browser. While it waits, the card says `Finish signing in in your browser` and the row under it is `Cancel Sign-In`. When Claude Code has no sign-in at all, the same item signs Claude Code itself in, so the new account is in use at once.
- **Saved automatically.** Once Claude is connected, the account Claude Code is signed in to is saved as soon as a read finds it missing from the list: on connect, on each refresh, and after Claude Code signs in to another account on its own. There is no save item.
- **Sign in.** When Claude Code has no sign-in, or its sign-in can't be read, the card has one row under it, `Sign In…`, which runs `Add Claude Account…`.
- **Not installed.** Without the `claude` command, `Add Claude Account…` is disabled with one line under it, `Install Claude Code first`.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting, `Allow Keychain access…`, and disconnecting read at once. Saved accounts that are not in use are read on the scheduled refresh, at most every 15 minutes, one at a time; an account just added is read at once.

## Source Contract

All knowledge of Claude Code's sign-in and of Anthropic's usage endpoint lives in `Sources/Platform/Claude`. Feature and UI code see parsed values only.

**Sign-in.** Refill looks in two places, in order, and never writes either:

1. `.credentials.json` in Claude Code's config folder: `CLAUDE_CONFIG_DIR` when Refill's environment sets it, otherwise `~/.claude`.
2. The login Keychain generic password with service `Claude Code-credentials` and account set to the macOS user name.

Both hold the same JSON. Refill decodes only `claudeAiOauth.accessToken`, `claudeAiOauth.expiresAt` (milliseconds since 1970), and `claudeAiOauth.subscriptionType`. It never decodes the refresh token. A file with no `claudeAiOauth`, for example one with only `mcpOAuth`, falls through to the Keychain; a Keychain item with none means signed out. A file or item that can't be read or isn't JSON is reported as unreadable, never skipped.

**Keychain prompts.** Only a user action may show the macOS Keychain prompt: confirming `Connect Claude Code?` or choosing `Allow Keychain access…`. Every other read first checks that the item exists by asking for its attributes, which needs no decryption. It then asks for the data with an `LAContext` whose `interactionNotAllowed` is set and `kSecUseAuthenticationUI` set to skip. If macOS still needs approval, the read reports Keychain access needed instead of prompting.

**Request.** `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`. The HTTP session has no cookie store and no URL cache. It follows a redirect only to the same host over HTTPS, so the token never reaches another host.

**Response.** `five_hour` and `seven_day` are each `{utilization, resets_at}`: `utilization` runs from 0 to 100 and `resets_at` is ISO 8601. Refill maps `five_hour` to `Session` (300 minutes) and `seven_day` to `Weekly` (10,080 minutes). Each `limits[]` entry with `kind` `weekly_scoped` is a per-model weekly limit: its name is `scope.model.display_name` (both Claude clients title it that way), its used share is `percent` and its reset is `resets_at`. Refill shows it as `<name> this week` (10,080 minutes), in response order after `Weekly`. An entry without a name or percent is skipped, a repeated name keeps the first, and a malformed `limits` never fails the read. The menu bar icon ignores these windows. It ignores other windows such as `seven_day_opus` and `seven_day_sonnet`. A null or missing window is left out. The plan name comes from `subscriptionType`, for example `max`.

## Read Policy

- Expired token (`expiresAt` in the past): no request. The menu shows sign-in expired, then Refill lets Claude Code renew it (see [Live Renewal](#live-renewal)).
- `401`: sign-in expired.
- `403`: access denied. Anthropic knows the token but won't share usage with it, for example a token without the profile scope.
- `429`: no request until `Retry-After` passes, given as seconds or an HTTP date, or 5 minutes when the header is missing or unreadable. The menu shows rate limited meanwhile.
- Network failure: unreachable. Another status: service error. An unreadable body: unexpected response. The shared provider runtime keeps the last good values for all of these.
- Refill holds the token only for the length of one read. It never stores, logs, displays, or refreshes it. `ClaudeAccessToken` prints as `ClaudeAccessToken(redacted)` and reflects no children.

## Live Renewal

Claude Code's access token lasts 8 hours, and Claude Code renews it only while it runs. So after a read finds the live sign-in expired, Refill runs `claude doctor` with Claude Code's own config (no `CLAUDE_CONFIG_DIR` unless Claude Code itself uses one). Claude Code renews an expired sign-in whenever it runs, without a model call, rotates the refresh token, and saves the result where it always does. Refill then reads usage again.

- Only when the token's `expiresAt` has passed, never early. A `401` on a token that has not expired does not count.
- Only when `claude` is installed and no terminal `claude` session runs, since a running one renews its own token. The Claude desktop app's own Claude Code, under `~/Library/Application Support/Claude/claude-code/`, is ignored because it keeps its own sign-in.
- At most once per expiry, and again for the same expiry only after 30 minutes, so a sign-in Claude Code can't renew does not run `claude doctor` on every read. It then stays `Claude Code sign-in expired`.
- Never while a sign-in, an account action, the inactive pass, or another renewal runs. Switching, adding, saving, and removing wait for a renewal to finish, so a switch saves the renewed sign-in.
- The expiry is read without the Keychain prompt. If the read needs the prompt, nothing runs.

## Isolated Runs

With `REFILL_ISOLATED_APP_SUPPORT_DIR` set, Refill never reads the real Claude sign-in or runs the real `claude`:

- The config folder is `CLAUDE_CONFIG_DIR` when set, otherwise `<root>/.claude`. Only its `.credentials.json` and `.claude.json` are read or written.
- The Keychain is skipped, so a missing file reads as signed out. An expired sign-in in that file shows the sign-in expired state without any request.
- Saved accounts are private files in `<root>/claude-code-accounts`, and the list is `<root>/claude-code-accounts.json`.
- The only `claude` it runs is `<root>/bin/claude`, so a test build can use a stand-in script. Without one, adding is disabled with `Install Claude Code first`.

## Claude Accounts

Each saved account is one Claude Code sign-in in Claude Code's own format, held by Refill: `claudeAiOauth` from Claude Code's credentials and `oauthAccount` from its global config, in one Refill Keychain item per account (`Refill Claude Code account`, account = the saved account's ID). The list in `claude-code-accounts.json` holds the name, email, organization, plan, account IDs, and the last limits read for each account, never tokens.

- **Adding by signing in.** Refill makes a folder `claude-sign-in/<uuid>` in its Application Support folder and runs `claude auth login --claudeai` with `CLAUDE_CONFIG_DIR` set to it, a minimal environment (none of the user's shell variables), stdin open and empty, and its output discarded. Claude Code opens the browser itself. On success Claude Code has saved the sign-in in the Keychain item `Claude Code-credentials-<first 8 hex of sha256(folder path)>` (or `.credentials.json` in the folder) and the account record in the folder's `.claude.json`. Refill reads both, saves them, then deletes that Keychain item with `/usr/bin/security delete-generic-password` and the folder. It deletes them also when the login fails, times out (15 minutes), or is cancelled. It reads the item with `security find-generic-password`, the tool that created it, so macOS shows no prompt.
- **Signing Claude Code in.** When Claude Code has no sign-in at all, adding runs the same command without `CLAUDE_CONFIG_DIR`, so Claude Code signs itself in, then saves that sign-in. A sign-in made in a throwaway folder could not be switched in, because a switch only updates Claude Code's existing Keychain item. Nothing is lost, since there was no sign-in.
- **Saving the live account.** After each read while Claude is connected, Refill compares the `oauthAccount` in Claude Code's global config with the saved list. When that account is not saved, it reads Claude Code's sign-in without the Keychain prompt and saves it. An account that is already saved is left alone, and a sign-in with no `oauthAccount` is not saved. It never runs during a sign-in, an account action, the inactive pass, or a live renewal, and those wait for it.
- **Matching.** Accounts match by Claude's account and organization IDs from `oauthAccount`. Tokens are never compared. Adding an account that is already saved replaces its saved sign-in. A sign-in with no `oauthAccount` is refused, since Refill can't tell which account it is.
- **Switching.** Refused while a terminal `claude` session runs, because a running Claude Code would write its old sign-in back. The desktop app's own Claude Code is ignored, as for renewal. If the process table can't be read, Claude Code counts as running. Otherwise the outgoing sign-in is saved again first, because Claude Code may have renewed it since. Then Refill writes the target's `claudeAiOauth` where Claude Code keeps its sign-in (its Keychain item or `.credentials.json`) and the target's `oauthAccount` into the global config, keeping every other key. An outgoing sign-in that is not saved yet is saved as a new account first, so it is never lost. The card's reading is dropped and read again for the new account.
- **Rollback.** If saving the outgoing copy, writing the list, writing the credentials, or writing the global config fails, every earlier step is put back byte for byte. If putting it back fails too, the error says so (`restoreFailed`).
- **Inactive accounts' limits.** Every 15 minutes, for each saved account Claude Code is not signed in to, Refill sends that account's own access token to `api/oauth/usage` and keeps the result in the list. The account in use is never read this way.
- **Renewal.** When a saved account's token has expired, Refill writes that saved sign-in into a new throwaway folder (`.credentials.json` and `.claude.json`, both private) and runs `claude doctor` there. Claude Code renews an expired sign-in whenever it runs, without a model call, and saves the result in that folder's Keychain item. Refill keeps it only if the token changed and the account is the same, and saves it only if the saved copy is still the one it started from (compare and swap). Then it deletes the folder and the item. When nothing was renewed, the account keeps its last limits, which age into `as of …`.
- **Races.** Switching, adding, or removing first lets the account being read finish and stops the rest, so a renewed sign-in is saved before any sign-in is touched. A new inactive pass waits while a sign-in, an account action, a live renewal, or a live account save runs.
- **Leftovers.** A folder left behind by a crash is deleted with its Keychain item when Refill next launches.
- **Errors.** Each failure has a short alert, for example `Quit Claude Code first` / `Close every claude session.` or `Claude sign-in didn't finish` / `Nothing was saved.` Cancelling shows nothing.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `ClaudeCredentialsTests` parse literal credentials, including the `mcpOAuth`-only case, prove the file wins over the Keychain, and prove the token appears in no `String(describing:)`, `String(reflecting:)`, or `dump` output of the credentials or the request.
- `ClaudeUsageAPITests` cover the response mapping, the request headers, the redirect rule, and status mapping for `401` and `429`. `RetryAfterTests` cover the shared `Retry-After` parser.
- `ClaudeCodeUsageTests` cover opt-in, the Keychain prompt only after a user action, the expiry gate, each failure state, the rate-limit wait, and that a switch changes whose limits the next read shows.
- `ClaudeCodeAccountStoreTests` cover saving, matching by account record, switching in the Keychain item and the credentials file, refusing while Claude Code runs, rollback with a failure injected at each step, and a scan proving no Claude source uses a refresh token or the token endpoint.
- `ClaudeCodeProcessDetectorTests` feed `ps` lines and check that terminal Claude Code counts in every install form, and that the Claude desktop app's own Claude Code does not.
- `ClaudeAccountsTests` run `ClaudeCodeUsage` against a fake `claude` that behaves like Claude Code 2.1.294: adding (success, cancel, failure, no account record, not installed, signing Claude Code in), cleanup of the folder and the right Keychain item every time, inactive reads with each account's own token, renewal with compare and swap, a switch racing a renewal, a switch saving the outgoing rotated sign-in, and live renewal (after expiry only, not while `claude` runs, the 30-minute retry, not during a sign-in, a save or the inactive pass, and a switch that waits for it).
- `ClaudeCodeProcessRunnerTests` run a stand-in `claude` script to check the exact `CLAUDE_CONFIG_DIR`, the minimal environment, and that cancelling stops a waiting login.
- `ProviderUsageMenuCopyTests` and `ClaudeCodeAccountAlertTests` check that every failure reads differently and stays a title plus one short line.
- A coordinator test walks the menu from `Add Account › Claude…` through declined consent, current usage, `Allow Keychain access…`, and disconnect, reading the built `NSMenu`.
- No test touches the network or the real Keychain.
