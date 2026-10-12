# Claude Usage

## User Story

As a Refill user who also works in Claude Code on a Pro or Max plan, I want to see my Claude 5-hour and weekly limits next to my Codex limits, so I can pick the tool with headroom without opening Claude Code's `/usage` screen.

## Product Contract

Claude Usage is an optional menu bar feature. When connected, Refill shows the 5-hour and weekly limits of the Claude account that Claude Code is signed in to.

Reading usage never changes anything in Claude Code. Refill never signs in to Claude, never renews a sign-in itself, and never calls Anthropic's token endpoint. If Claude Code's sign-in is missing, Refill says so and points the user back to Claude Code. When it has expired and no terminal `claude` runs, Refill runs `claude doctor` so Claude Code renews it, described in [Live Renewal](#live-renewal). Refill shows only the account Claude Code is signed in to, by its email. It never saves, adds, or switches Claude accounts, and it never writes Claude Code's files or Keychain item.

The feature is off by default. Connecting it is the user's consent for Refill to read Claude Code's sign-in and send it to Anthropic.

Claude usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

Refill never reads or writes Claude Code's `settings.json`. Reading limits from Anthropic, rather than from Claude Code's status line, means usage stays current when Claude Code runs in the Claude desktop app or remotely.

## Menu

The `Claude` card follows the shared card and side menu in [Menubar](menubar.md). The side menu shows the email Claude Code is signed in to, checked and disabled, then the model limit toggle and the moves. It has no account actions. `Appearance › Show Tools › Claude` disconnects it.

- **Not connected.** There is no card. Checking `Appearance › Show Tools › Claude` connects. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Claude Code?**
  > Uses Claude Code's sign-in to read your limits.

  Confirming saves the choice and reads at once.
- **Connected.** The choice is saved in user defaults (`claudeUsageEnabled`, off by default). Unchecking `Appearance › Show Tools › Claude` turns the feature off at once with no alert, because it changes nothing outside Refill. Checking it again connects through the same consent alert.
- **Current.** The plan tag (`Max x20`, read from `organizationRateLimitTier`, else `userRateLimitTier`, in Claude Code's `oauthAccount`, because the credentials' `rateLimitTier` keeps the tier from sign-in time; that one is used only when the account record has none), then `Session` and `Weekly` meters with their reset times, then one meter per model with its own weekly limit, such as `Fable this week`, unless the side menu's model limit toggle is off. There is no reset-credit row. The meters use the same percent mode, layout, colors, and pacing markers as the Codex card.
- **Waiting.** `Waiting for Claude Code usage`, with no second line. Anthropic answered but sent neither window, for example on a plan without subscription limits.
- **Keychain access needed.** `security` was refused or timed out, for example on a locked Keychain. With an earlier reading, the card keeps it dimmed under its `As of` time. Without one, it says `Allow Keychain access`. Either way, one row under it, `Allow Keychain Access…`, reads again and waits up to 2 minutes so the user can answer a macOS prompt.
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
- **`Show Fable Limits`** sits in the side menu after the email and is checked while on. It is named after every model with its own limit in the current reading, from `limits[].scope.model.display_name`: `Show Fable and Opus Limits` for two, `Show Fable, Opus and Sonnet Limits` for three. One toggle covers them all, because the choice is one saved setting. It is hidden when the reading has no model limit. Turning it off hides the per-model meters in the card. It never changes the menu bar icon, which uses only the session and weekly windows. It is on by default and saved as `claudeShowsModelLimits` in user defaults.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting, `Allow Keychain Access…`, and disconnecting read at once.

Anthropic also has Claude reset credits, but it withholds them from Claude Code's sign-in (`eligible=false`, `ineligible_reason=surface`), so Refill doesn't show them.

## Source Contract

All knowledge of Claude Code's sign-in and of Anthropic's usage endpoint lives in `Sources/Platform/Claude`. Feature and UI code see parsed values only.

**Sign-in.** Refill looks in two places, in order, and never writes either:

1. `.credentials.json` in Claude Code's config folder: `CLAUDE_CONFIG_DIR` when Refill's environment sets it, otherwise `~/.claude`.
2. The login Keychain generic password with service `Claude Code-credentials` and account set to the macOS user name.

Both hold the same JSON. Refill decodes only `claudeAiOauth.accessToken`, `claudeAiOauth.expiresAt` (milliseconds since 1970), `claudeAiOauth.subscriptionType`, and `claudeAiOauth.rateLimitTier`. From `oauthAccount` in Claude Code's global config (`$CLAUDE_CONFIG_DIR/.claude.json`, or `~/.claude.json`) it decodes only the two rate-limit tiers and `emailAddress`, which the side menu shows. It never decodes the refresh token. A file with no `claudeAiOauth`, for example one with only `mcpOAuth`, falls through to the Keychain; a Keychain item with none means signed out. A file or item that can't be read or isn't JSON is reported as unreadable, never skipped.

**Keychain reads.** Refill reads Claude Code's item by running `/usr/bin/security find-generic-password -a <user> -s <service> -w`, as Claude Code does, with the password coming back through a pipe (`ClaudeCodeSecurityKeychain`). Claude Code writes its items with `security`, so only `security` is on their access list. A direct Keychain API read from Refill showed a macOS prompt for such an item even with `kSecUseAuthenticationUI` set to skip, and every renewal could take back an earlier `Always Allow`. `security` prints a password that is not plain text as hex, and Refill decodes it. Exit 44 (item not found) means signed out. Exits 36, 51 and 128 (interaction not allowed, refused, cancelled) and a timeout mean Keychain access needed. A timeout is 10 seconds for a background read and 2 minutes after a click. Anything else means unreadable. `security` has no switch to forbid its prompt. It shows none for items it created, which covers every item Claude Code writes.

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
- One renewal at a time.
- The expiry is read without the Keychain prompt. If the read needs the prompt, nothing runs.
- `claude` runs with a minimal environment (none of the user's shell variables), stdin open and empty, and its output discarded.

## Isolated Runs

With `REFILL_ISOLATED_APP_SUPPORT_DIR` set, Refill never reads the real Claude sign-in or runs the real `claude`:

- The config folder is `CLAUDE_CONFIG_DIR` when set, otherwise `<root>/.claude`. Only its `.credentials.json` and `.claude.json` are read.
- The Keychain is skipped, so a missing file reads as signed out. An expired sign-in in that file shows the sign-in expired state without any request.
- The only `claude` it runs is `<root>/bin/claude`, so a test build can use a stand-in script for renewal.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `ClaudeCredentialsTests` parse literal credentials, including the `mcpOAuth`-only case, prove the file wins over the Keychain, and prove the token appears in no `String(describing:)`, `String(reflecting:)`, or `dump` output of the credentials or the request.
- `ClaudeUsageAPITests` cover the response mapping, the request headers, the redirect rule, and status mapping for `401` and `429`. `RetryAfterTests` cover the shared `Retry-After` parser.
- `ClaudeCodeUsageTests` cover opt-in, the Keychain prompt only after a user action, the expiry gate, each failure state, and the rate-limit wait. A scan in `ClaudeCredentialsTests` proves no Claude source uses a refresh token, and other `ClaudeCredentialsTests` read the plan tier and the email from the account record.
- `ClaudeLiveRenewalTests` run `ClaudeCodeUsage` against a fake `claude`: renewal after expiry only, not while `claude` runs, the 30-minute retry, and a fresh read once Claude Code renewed.
- `ClaudeCodeProcessDetectorTests` feed `ps` lines and check that terminal Claude Code counts in every install form, and that the Claude desktop app's own Claude Code does not.
- `ClaudeCodeProcessRunnerTests` run a stand-in `claude` script to check the exact `CLAUDE_CONFIG_DIR`, the minimal environment, and that cancelling stops a waiting run.
- `ProviderCopyTests` checks that every failure reads differently and stays a title plus one short line.
- `ClaudeCodeSecurityKeychainTests` check the `security` arguments and timeouts, text and hex passwords, and that each exit status reads as signed out, access needed or unreadable.
- `UsageReadFailureTests` check that a failed read logs only its category, such as `http 503`.
- A coordinator test walks the menu from `Appearance › Show Tools › Claude` through declined consent, current usage, `Allow Keychain Access…`, and disconnect, reading the built `NSMenu`.
- No test touches the network or the real Keychain.
