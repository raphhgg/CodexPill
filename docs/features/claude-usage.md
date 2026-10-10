# Claude Usage

## User Story

As a CodexPill user who also works in Claude Code on a Pro or Max plan, I want to see my Claude 5-hour and weekly limits next to my Codex limits, so I can pick the tool with headroom without opening Claude Code's `/usage` screen.

## Product Contract

Claude Usage is an optional menu bar feature. When connected, CodexPill shows the 5-hour and weekly limits of the Claude account that Claude Code is signed in to.

Reading usage never changes anything in Claude Code. CodexPill never signs in to Claude and never renews Claude Code's sign-in. If Claude Code's sign-in is missing or expired, CodexPill says so and points the user back to Claude Code. Switching Claude Code between saved sign-ins is a separate, explicit action, described in [Claude Code Account Switching](#claude-code-account-switching).

The feature is off by default. Connecting it is the user's consent for CodexPill to read Claude Code's sign-in and send it to Anthropic.

Claude usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

CodexPill never reads or writes Claude Code's `settings.json`. Reading limits from Anthropic, rather than from Claude Code's status line, means usage stays current when Claude Code runs in the Claude desktop app or remotely.

## Menu

A `Claude Code` section sits below the saved accounts. It has no switching actions.

- **Not connected.** The section shows `Connect Claude Code…`. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Claude Code?**
  > Uses Claude Code's sign-in to read your limits.

  Confirming saves the choice and reads at once. That first read may show the macOS Keychain prompt.
- **Connected.** The choice is saved in user defaults (`claudeUsageEnabled`, off by default). `Preferences` gains `Disconnect Claude Code…`, which turns the feature off at once with no alert, because it changes nothing outside CodexPill.
- **Current.** A caption with the plan and the read time (`Max plan · As of 10:42`), then `Session` and `Weekly` meters with their reset times. The meters use the same percent mode, layout, colors, and pacing markers as the Codex card.
- **Waiting.** `Waiting for Claude Code usage`, with no second line. Anthropic answered but sent neither window, for example on a plan without subscription limits.
- **Keychain access needed.** One action, `Allow Keychain access…`. It reads again with the macOS Keychain prompt allowed. Claude Code rewrites its Keychain item when it renews its sign-in, which can reset an earlier `Always Allow`, so this state can come back.
- **Failures.** Each failure shows a title and one short line. Except for signed out, the last good values stay dimmed below it with their `As of` time.

  | Cause | Title | Second line |
  |---|---|---|
  | No sign-in | `Not signed in to Claude Code` | `Sign in to Claude Code to see usage.` |
  | Token past its expiry, or `401` | `Claude Code sign-in expired` | `Open Claude Code to renew it.` |
  | Credentials file or Keychain item unreadable or not JSON | `Can't read the Claude Code sign-in` | `Sign in to Claude Code again.` |
  | `403` | `Anthropic won't share usage` | `Sign in to Claude Code again.` |
  | `429`, or waiting out `Retry-After` | `Anthropic asked to wait` | `Retrying in a few minutes.` |
  | No answer (offline, DNS, TLS, timeout) | `Can't reach Anthropic` | `Retrying in a few minutes.` |
  | Any other status | `Anthropic is having trouble` | `Retrying in a few minutes.` |
  | A `200` that is not the usage shape | `Unexpected reply from Anthropic` | `Retrying in a few minutes.` |
- **Stale.** A snapshot older than 15 minutes is dimmed. Its label still reads `As of …` until the next read.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting, `Allow Keychain access…`, and disconnecting read at once.

## Source Contract

All knowledge of Claude Code's sign-in and of Anthropic's usage endpoint lives in `Sources/Platform/Claude`. Feature and UI code see parsed values only.

**Sign-in.** CodexPill looks in two places, in order, and never writes either:

1. `.credentials.json` in Claude Code's config folder: `CLAUDE_CONFIG_DIR` when CodexPill's environment sets it, otherwise `~/.claude`.
2. The login Keychain generic password with service `Claude Code-credentials` and account set to the macOS user name.

Both hold the same JSON. CodexPill decodes only `claudeAiOauth.accessToken`, `claudeAiOauth.expiresAt` (milliseconds since 1970), and `claudeAiOauth.subscriptionType`. It never decodes the refresh token. A file with no `claudeAiOauth`, for example one with only `mcpOAuth`, falls through to the Keychain; a Keychain item with none means signed out. A file or item that can't be read or isn't JSON is reported as unreadable, never skipped.

**Keychain prompts.** Only a user action may show the macOS Keychain prompt: confirming `Connect Claude Code?` or choosing `Allow Keychain access…`. Every other read first checks that the item exists by asking for its attributes, which needs no decryption. It then asks for the data with an `LAContext` whose `interactionNotAllowed` is set and `kSecUseAuthenticationUI` set to skip. If macOS still needs approval, the read reports Keychain access needed instead of prompting.

**Request.** `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`. The HTTP session has no cookie store and no URL cache. It follows a redirect only to the same host over HTTPS, so the token never reaches another host.

**Response.** `five_hour` and `seven_day` are each `{utilization, resets_at}`: `utilization` runs from 0 to 100 and `resets_at` is ISO 8601. CodexPill maps `five_hour` to `Session` (300 minutes) and `seven_day` to `Weekly` (10,080 minutes). It ignores other windows such as `seven_day_opus` and `seven_day_sonnet`. A null or missing window is left out. The plan name comes from `subscriptionType`, for example `max`.

## Read Policy

- Expired token (`expiresAt` in the past): no request. The menu shows sign-in expired. Claude Code renews the token the next time it runs.
- `401`: sign-in expired.
- `403`: access denied. Anthropic knows the token but won't share usage with it, for example a token without the profile scope.
- `429`: no request until `Retry-After` passes, given as seconds or an HTTP date, or 5 minutes when the header is missing or unreadable. The menu shows rate limited meanwhile.
- Network failure: unreachable. Another status: service error. An unreadable body: unexpected response. The shared provider runtime keeps the last good values for all of these.
- CodexPill holds the token only for the length of one read. It never stores, logs, displays, or refreshes it. `ClaudeAccessToken` prints as `ClaudeAccessToken(redacted)` and reflects no children.

## Isolated Runs

With `CODEXPILL_ISOLATED_APP_SUPPORT_DIR` set, CodexPill never reads the real Claude sign-in:

- The config folder is `CLAUDE_CONFIG_DIR` when set, otherwise `<root>/.claude`. Only its `.credentials.json` is read.
- The Keychain is skipped, so a missing file reads as signed out. An expired sign-in in that file shows the sign-in expired state without any request.
- There is no account switching, so an isolated run never writes a Keychain item.

## Claude Code Account Switching

CodexPill can save Claude Code sign-ins and switch Claude Code between them, the way it switches Codex accounts through `auth.json`. This is the data layer only. No menu shows it yet; `ClaudeCodeUsage.accounts` and `ClaudeCodeUsage.switchAccount(to:)` are the entry points a menu uses. It works whether or not Claude usage is connected.

- **Saving.** Reads Claude Code's current sign-in and its `oauthAccount`, and stores both in a CodexPill Keychain item (`CodexPill Claude Code account`, one per account). The list in `claude-code-accounts.json` holds the name, email, organization, plan, and account IDs, never tokens. Saving an account that is already saved refreshes its copy. A sign-in whose global config records no `oauthAccount` is refused, since CodexPill can't tell which account it is.
- **Matching.** Accounts match by Claude's account and organization IDs from `oauthAccount`. Tokens are never compared.
- **Switching.** Refused while any `claude` process runs, because a running Claude Code would write its old sign-in back. Otherwise the outgoing sign-in is saved again first, because Claude Code may have renewed it since. Then CodexPill writes the target's `claudeAiOauth` where Claude Code keeps its sign-in (its Keychain item or `.credentials.json`) and the target's `oauthAccount` into the global config, keeping every other key. A sign-in that is not saved is never overwritten.
- **Rollback.** If saving the outgoing copy, writing the list, writing the credentials, or writing the global config fails, every earlier step is put back byte for byte. If putting it back fails too, the error says so (`restoreFailed`).
- **After a switch.** The next usage read may show the Keychain prompt, since the switch rewrote Claude Code's item.
- **Errors.** Each `ClaudeCodeAccountError` has a short alert from `MenuBarAlertFactory.makeClaudeCodeAccountErrorRequest`, for example `Quit Claude Code first` / `Close every claude session.`

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `ClaudeCredentialsTests` parse literal credentials, including the `mcpOAuth`-only case, prove the file wins over the Keychain, and prove the token appears in no `String(describing:)`, `String(reflecting:)`, or `dump` output of the credentials or the request.
- `ClaudeUsageAPITests` cover the response mapping, the request headers, the redirect rule, and status mapping for `401` and `429`. `RetryAfterTests` cover the shared `Retry-After` parser.
- `ClaudeCodeUsageTests` cover opt-in, the Keychain prompt only after a user action, the expiry gate, each failure state, the rate-limit wait, and that a switch changes whose limits the next read shows.
- `ClaudeCodeAccountStoreTests` cover saving, matching by account record, switching in the Keychain item and the credentials file, refusing while Claude Code runs, rollback with a failure injected at each step, and a scan proving no Claude source uses a refresh token.
- `ProviderUsageMenuCopyTests` and `ClaudeCodeAccountAlertTests` check that every failure reads differently and stays a title plus one short line.
- A coordinator test walks the menu from `Connect Claude Code…` through declined consent, current usage, `Allow Keychain access…`, and disconnect, reading the built `NSMenu`.
- No test touches the network or the real Keychain.
