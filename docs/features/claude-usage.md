# Claude Usage

## User Story

As a CodexPill user who also works in Claude Code on a Pro or Max plan, I want to see my Claude 5-hour and weekly limits next to my Codex limits, so I can pick the tool with headroom without opening Claude Code's `/usage` screen.

## Product Contract

Claude Usage is an optional menu bar feature. When connected, CodexPill shows the 5-hour and weekly limits of one Claude account, read with one of two sign-ins:

- **Claude Code's sign-in**, read only, for people who use the `claude` terminal app. CodexPill never renews it. If it is missing or expired, CodexPill says so and points the user back to Claude Code.
- **CodexPill's own sign-in**, made with "Sign in with Claude" in the browser and kept in CodexPill's Keychain item. CodexPill refreshes it itself, so the numbers keep updating when the user works only in the Claude desktop app or on the web.

The connection remembers which one it uses and never falls back to the other, because the other may be a different Claude account. Reading usage never changes anything in Claude Code. Switching Claude Code between saved sign-ins is a separate, explicit action, described in [Claude Code Account Switching](#claude-code-account-switching).

The feature is off by default. Connecting it is the user's consent for CodexPill to read Claude Code's sign-in, or to sign in to Claude, and to send the token to Anthropic.

Claude usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

CodexPill never reads or writes Claude Code's `settings.json`. Reading limits from Anthropic, rather than from Claude Code's status line, means usage stays current when Claude Code runs in the Claude desktop app or remotely.

## Menu

The `Claude` card follows the shared card and side menu in [Menubar](menubar.md). The side menu switches between saved Claude Code sign-ins and ends with `Disconnect Claude`.

- **Not connected.** There is no card. `Settings › Add Account › Claude…` (and the first-run `Add Account ›`) connects. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Claude Code?**
  > Uses Claude Code's sign-in, or your browser if it has none.

  Confirming first checks Claude Code's sign-in, which may show the macOS Keychain prompt. If it is there and unexpired, Claude connects with it and reads at once. Otherwise the browser opens on Claude's sign-in page, and Claude connects only once that sign-in succeeds.
- **Signing in.** The card says `Finish signing in in your browser`, with one row under it, `Cancel Sign-In`. The sign-in gives up after 5 minutes. A failure shows a short alert (`Claude sign-in timed out` / `Start it again from the menu.`). Cancelling shows nothing. If the Keychain refuses to save the new sign-in, Claude still connects and an alert says `Claude sign-in not saved` / `It lasts until CodexPill quits.`
- **Connected.** The choice and its sign-in are saved in user defaults (`claudeUsageEnabled`, `claudeUsageSignInSource`, off by default). The side menu ends with `Disconnect Claude`. It turns the feature off at once with no alert, deletes CodexPill's own Keychain item, and asks Anthropic to revoke that sign-in. Claude Code's sign-in is left alone. If the Keychain item can't be deleted, an alert says so.
- **Current.** The plan tag (`Max x20`, read from Claude Code's `rateLimitTier`, so only with Claude Code's sign-in), then `Session` and `Weekly` meters with their reset times. There is no reset-credit row. The meters use the same percent mode, layout, colors, and pacing markers as the Codex card.
- **Waiting.** `Waiting for Claude Code usage`, with no second line. Anthropic answered but sent neither window, for example on a plan without subscription limits.
- **Sign in again.** The card says `Sign in to Claude again`, with one row under it, `Sign In…`, which starts the browser sign-in at once. Shown while connected with CodexPill's own sign-in when its item is gone, Anthropic rejects its refresh token (`invalid_grant`), or a token is still rejected after one refresh. It stays until the user signs in again or disconnects. The last values are cleared, because the next sign-in may be another account.
- **Keychain access needed.** The card says `Allow Keychain access` and one row under it, `Allow Keychain access…`. It reads again with the macOS Keychain prompt allowed. Claude Code rewrites its Keychain item when it renews its sign-in, which can reset an earlier `Always Allow`, so this state can come back.
- **Failures.** Each failure shows a title and one short line. Except for signed out and sign in again, the last good values stay dimmed below it with their `As of` time. Signed out and sign-in expired also offer `Sign In…`, which switches the connection to CodexPill's own sign-in once it succeeds.

  | Cause | Title | Second line |
  |---|---|---|
  | No sign-in | `Not signed in to Claude Code` | `Sign in to Claude Code to see usage.` |
  | Token past its expiry, or `401` | `Claude Code sign-in expired` | `Open Claude Code to renew it.` |
  | Credentials file or either Keychain item unreadable or not JSON | `Can't read the Claude Code sign-in` | `Sign in to Claude Code again.` |
  | `403` | `Anthropic won't share usage` | `Sign in to Claude Code again.` |
  | `429`, or waiting out `Retry-After` | `Anthropic asked to wait` | `Retrying in a few minutes.` |
  | No answer (offline, DNS, TLS, timeout) | `Can't reach Anthropic` | `Retrying in a few minutes.` |
  | Any other status | `Anthropic is having trouble` | `Retrying in a few minutes.` |
  | A `200` that is not the usage shape | `Unexpected reply from Anthropic` | `Retrying in a few minutes.` |
- **Stale.** A snapshot older than 15 minutes is dimmed. Its label still reads `As of …` until the next read.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting, signing in, `Allow Keychain access…`, and disconnecting read at once.

## Source Contract

All knowledge of Claude's OAuth, both sign-ins, and Anthropic's usage endpoint lives in `Sources/Platform/Claude`. Feature and UI code see parsed values only.

**Sign in with Claude.** OAuth 2.0 authorization code with PKCE (S256), with the public client Claude Code uses:

- Client id `9d1c250a-e61b-44d9-88ed-5944d1962f5e`.
- Authorize page `https://claude.com/cai/oauth/authorize` with `code=true`, `client_id`, `response_type=code`, `redirect_uri`, `scope=user:profile`, `code_challenge`, `code_challenge_method=S256`, and `state`. `user:profile` is the only scope `api/oauth/usage` needs, and the only one CodexPill asks for.
- Redirect `http://localhost:<port>/callback`. A one-shot `NWListener` accepts loopback connections only, on a free port the system picks. It answers the callback with a short "Signed in to Claude" page, answers any other path with `404`, and stops after the first callback.
- The callback must carry the `state` this sign-in sent, otherwise the code is never exchanged. `error=access_denied` ends the sign-in.
- Token endpoint `https://platform.claude.com/v1/oauth/token`, JSON bodies. Exchange: `grant_type=authorization_code`, `code`, `redirect_uri`, `client_id`, `code_verifier`, `state`. Refresh: `grant_type=refresh_token`, `refresh_token`, `client_id`, `scope`. A refresh that omits `refresh_token` keeps the current one.
- Revoke `https://platform.claude.com/v1/oauth/token/revoke` with `token`, `token_type_hint=refresh_token`, and `client_id`, best effort on disconnect.

**CodexPill's sign-in item.** A generic password in the login Keychain, service `CodexPill Claude sign-in`, account `Claude`, holding JSON with the access token, refresh token, and expiry. Never a file. Refreshes run one at a time, so a rotated refresh token is never spent twice. If the Keychain refuses to save a rotation, CodexPill keeps it in memory and retries the save on the next read.

**Claude Code's sign-in, read only.** CodexPill looks in two places, in order, and never writes either outside a switch:

1. `.credentials.json` in Claude Code's config folder: `CLAUDE_CONFIG_DIR` when CodexPill's environment sets it, otherwise `~/.claude`.
2. The login Keychain generic password with service `Claude Code-credentials` and account set to the macOS user name.

Both hold the same JSON. CodexPill decodes only `claudeAiOauth.accessToken`, `claudeAiOauth.expiresAt` (milliseconds since 1970), and `claudeAiOauth.subscriptionType`. It never decodes the refresh token. A file with no `claudeAiOauth`, for example one with only `mcpOAuth`, falls through to the Keychain; a Keychain item with none means signed out. A file or item that can't be read or isn't JSON is reported as unreadable, never skipped.

**Keychain prompts.** Only a user action may show the macOS Keychain prompt: confirming `Connect Claude Code?`, finishing a sign-in, or choosing `Allow Keychain access…`. Every other read first checks that the item exists by asking for its attributes, which needs no decryption. It then asks for the data with an `LAContext` whose `interactionNotAllowed` is set and `kSecUseAuthenticationUI` set to skip. If macOS still needs approval, the read reports Keychain access needed instead of prompting.

**Request.** `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`. Every request that carries a token uses a session with no cookie store and no URL cache. It follows a redirect only to the same host over HTTPS, so the token never reaches another host.

**Response.** `five_hour` and `seven_day` are each `{utilization, resets_at}`: `utilization` runs from 0 to 100 and `resets_at` is ISO 8601. CodexPill maps `five_hour` to `Session` (300 minutes) and `seven_day` to `Weekly` (10,080 minutes). It ignores other windows such as `seven_day_opus` and `seven_day_sonnet`. A null or missing window is left out. The plan name comes from `subscriptionType`, for example `max`.

## Read Policy

- Claude Code's expired token (`expiresAt` in the past): no request. The menu shows sign-in expired. Claude Code renews the token the next time it runs.
- `401` with Claude Code's sign-in: sign-in expired. CodexPill never refreshes Claude Code's token.
- CodexPill's own sign-in within 5 minutes of expiry: refresh first. `invalid_grant` deletes the item and shows sign in again. Another refresh failure keeps using the current access token until it expires, then shows unreachable, service error, or unexpected response.
- `401` with CodexPill's own sign-in: one refresh, then one retry. A failed refresh or a second `401` shows sign in again, unless the refresh could not reach Anthropic, which shows unreachable. A read that already refreshed does not refresh again.
- `403`: access denied. Anthropic knows the token but won't share usage with it, for example a token without the profile scope.
- `429`: no request until `Retry-After` passes, given as seconds or an HTTP date, or 5 minutes when the header is missing or unreadable. The menu shows rate limited meanwhile.
- Network failure: unreachable. Another status: service error. An unreadable body: unexpected response. The shared provider runtime keeps the last good values for all of these.
- CodexPill holds Claude Code's token only for the length of one read, and never stores or refreshes it. No token is ever logged, printed, or displayed. `ClaudeAccessToken`, `ClaudeRefreshToken`, and `ClaudePKCE` print as `<Type>(redacted)` and reflect no children.

## Isolated Runs

With `CODEXPILL_ISOLATED_APP_SUPPORT_DIR` set, CodexPill never reads the real Claude sign-in:

- The config folder is `CLAUDE_CONFIG_DIR` when set, otherwise `<root>/.claude`. Only its `.credentials.json` is read.
- The Keychain is skipped, so a missing file reads as signed out. An expired sign-in in that file shows the sign-in expired state without any request.
- CodexPill's own sign-in lives in memory only and is gone when the app quits. "Sign in with Claude" still opens the real browser and the real token endpoint, so do not finish it with a real account in a test run.
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

- `ClaudeOAuthTests` check the PKCE challenge against RFC 7636's example, the exact authorize URL, callback parsing, `state` mismatch rejection, token response parsing, `invalid_grant`, the token request bodies, the refresh-before-expiry rule, that no token appears when a sign-in or its requests are printed, and the real loopback listener.
- `ClaudeCredentialsTests` parse literal credentials, including the `mcpOAuth`-only case, prove the file wins over the Keychain, and prove the token appears in no `String(describing:)`, `String(reflecting:)`, or `dump` output of the credentials or the request.
- `ClaudeUsageAPITests` cover the response mapping, the request headers, the redirect rule, and status mapping for `401` and `429`. `RetryAfterTests` cover the shared `Retry-After` parser.
- `ClaudeCodeUsageTests` cover opt-in, each connection reading only its own sign-in, no fallback after `invalid_grant`, one refresh and retry on a `401`, refresh failures, one shared refresh for two reads, sign-in failures and cancellation, disconnect, the Keychain prompt only after a user action, the expiry gate, each failure state, the rate-limit wait, and that a switch changes whose limits the next read shows.
- `ClaudeCodeAccountStoreTests` cover saving, matching by account record, switching in the Keychain item and the credentials file, refusing while Claude Code runs, rollback with a failure injected at each step, and a scan proving refresh-token code exists only in the files that own CodexPill's sign-in, and that a refresh token comes only from CodexPill's item or Claude's token response.
- `ProviderCopyTests` check that every failure reads differently and that every alert stays a title plus one short line. `ToolSectionTests` check which states offer `Sign In…`.
- Two coordinator tests walk the built `NSMenu` from `Add Account › Claude…`: consent, `Cancel Sign-In`, a declined sign-in alert, current usage, `Sign In…` after the sign-in expired, disconnect, and `Allow Keychain access…`.
- No test touches Anthropic or a real Keychain item, except one that opens the loopback listener on this Mac.
