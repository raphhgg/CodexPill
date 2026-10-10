# Claude Usage

## User Story

As a CodexPill user who also works in Claude Code on a Pro or Max plan, I want to see my Claude 5-hour and weekly limits next to my Codex limits, so I can pick the tool with headroom without opening Claude Code's `/usage` screen.

## Product Contract

Claude Usage is an optional, display-only menu bar feature. When connected, CodexPill shows the 5-hour and weekly limits of the Claude account that Claude Code is signed in to.

CodexPill does not switch Claude accounts, sign in to Claude, refresh Claude Code's sign-in, or change anything in Claude Code. If Claude Code's sign-in is missing or expired, CodexPill says so and points the user back to Claude Code.

The feature is off by default. Connecting it is the user's consent for CodexPill to read Claude Code's sign-in and send it to Anthropic.

Claude usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

This replaces the earlier status line relay. The relay only saw sessions that ran Claude Code's status line, so it never updated from the Claude desktop app or remote sessions. CodexPill no longer reads or writes Claude Code's `settings.json`. Anyone who installed the relay removes it from Claude Code's `statusLine` setting by hand.

## Menu

A `Claude Code` section sits below the saved accounts. It has no switching actions.

- **Not connected.** The section shows `Connect Claude Code…`. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Claude Code?**
  > CodexPill will read Claude Code's sign-in from your Keychain to show your 5-hour and weekly limits. It never stores or shares it.

  Confirming saves the choice and reads at once. That first read may show the macOS Keychain prompt.
- **Connected.** The choice is saved in user defaults (`claudeUsageEnabled`, off by default). `Preferences` gains `Disconnect Claude Code…`, which turns the feature off at once with no alert, because it changes nothing outside CodexPill.
- **Current.** A caption with the plan and the read time (`Max plan · As of 10:42`), then `Session` and `Weekly` meters with their reset times. The meters use the same percent mode, layout, colors, and pacing markers as the Codex card.
- **Waiting.** `Waiting for Claude usage`, with no second line. Anthropic answered but sent neither window, for example on a plan without subscription limits.
- **Keychain access needed.** One action, `Allow Keychain access…`. It reads again with the macOS Keychain prompt allowed. Claude Code rewrites its Keychain item when it renews its sign-in, which can reset an earlier `Always Allow`, so this state can come back.
- **Signed out.** `Not signed in to Claude Code` / `Sign in to Claude Code to see usage.` Last good values are cleared.
- **Sign-in expired or rejected.** `Sign in to Claude Code again` / `Open Claude Code to sign in again.`, with the last good values dimmed below it.
- **Read failed** (network, rate limit, unexpected response). `Can't reach Anthropic` / `Retrying in a few minutes.`, with the last good values dimmed below it and their `As of` time.
- **Stale.** A snapshot older than 15 minutes is dimmed. Its label still reads `As of …` until the next read.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting, `Allow Keychain access…`, and disconnecting read at once.

## Source Contract

All knowledge of Claude Code's sign-in and of Anthropic's usage endpoint lives in `Sources/Platform/Claude`. Feature and UI code see parsed values only.

**Sign-in.** CodexPill looks in two places, in order, and never writes either:

1. `.credentials.json` in Claude Code's config folder: `CLAUDE_CONFIG_DIR` when CodexPill's environment sets it, otherwise `~/.claude`.
2. The login Keychain generic password with service `Claude Code-credentials` and account set to the macOS user name.

Both hold the same JSON. CodexPill decodes only `claudeAiOauth.accessToken`, `claudeAiOauth.expiresAt` (milliseconds since 1970), and `claudeAiOauth.subscriptionType`. It never decodes the refresh token. An item with no `claudeAiOauth`, for example one with only `mcpOAuth`, means signed out.

**Keychain prompts.** Only a user action may show the macOS Keychain prompt: confirming `Connect Claude Code?` or choosing `Allow Keychain access…`. Every other read first checks that the item exists by asking for its attributes, which needs no decryption. It then asks for the data with an `LAContext` whose `interactionNotAllowed` is set and `kSecUseAuthenticationUI` set to skip. If macOS still needs approval, the read reports Keychain access needed instead of prompting.

**Request.** `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`. The HTTP session has no cookie store and no URL cache. It follows a redirect only to the same host over HTTPS, so the token never reaches another host.

**Response.** `five_hour` and `seven_day` are each `{utilization, resets_at}`: `utilization` runs from 0 to 100 and `resets_at` is ISO 8601. CodexPill maps `five_hour` to `Session` (300 minutes) and `seven_day` to `Weekly` (10,080 minutes). It ignores other windows such as `seven_day_opus` and `seven_day_sonnet`. A null or missing window is left out. The plan name comes from `subscriptionType`, for example `max`.

## Read Policy

- Expired token (`expiresAt` in the past): no request. The menu shows sign-in expired. Claude Code renews the token the next time it runs.
- `401`: sign-in expired.
- `429`: no request until `Retry-After` seconds pass, or 5 minutes when the header is missing or not a number. The menu shows read failed meanwhile.
- Network failure, another status, or an unreadable body: read failed. The shared provider runtime keeps the last good values.
- CodexPill holds the token only for the length of one read. It never stores, logs, displays, or refreshes it. `ClaudeAccessToken` prints as `ClaudeAccessToken(redacted)` and reflects no children.

## Isolated Runs

With `CODEXPILL_ISOLATED_APP_SUPPORT_DIR` set, CodexPill never reads the real Claude sign-in:

- The config folder is `CLAUDE_CONFIG_DIR` when set, otherwise `<root>/.claude`. Only its `.credentials.json` is read.
- The Keychain is skipped, so a missing file reads as signed out.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `ClaudeCredentialsTests` parse literal credentials, including the `mcpOAuth`-only case, prove the file wins over the Keychain, and prove the token appears in no `String(describing:)`, `String(reflecting:)`, or `dump` output of the credentials or the request.
- `ClaudeUsageAPITests` cover the response mapping, the request headers, the redirect rule, and status mapping for `401` and `429` with and without `Retry-After`.
- `ClaudeCodeUsageTests` cover opt-in, the Keychain prompt only after a user action, the expiry gate, each failure state, and the rate-limit wait.
- A coordinator test walks the menu from `Connect Claude Code…` through declined consent, current usage, `Allow Keychain access…`, and disconnect, reading the built `NSMenu`.
- No test touches the network or the real Keychain.
