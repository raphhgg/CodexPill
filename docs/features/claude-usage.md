# Claude Usage

## User Story

As a CodexPill user who also works with Claude on a Pro or Max plan, I want to see my Claude 5-hour and weekly limits next to my Codex limits, so I can pick the tool with headroom without opening Claude's usage screen.

## Product Contract

Claude Usage is an optional, display-only menu bar feature. When connected, CodexPill shows the 5-hour and weekly limits of one Claude account.

CodexPill keeps its own Claude sign-in, made with "Sign in with Claude" in the browser. It refreshes that sign-in itself, so the numbers keep updating whether the user works in the Claude desktop app, the web, or the terminal. People who use the `claude` terminal app need no second sign-in: while Claude Code's own sign-in is unexpired, CodexPill can read usage with it instead.

CodexPill does not switch Claude accounts or change anything in Claude Code. It never writes, refreshes, or stores Claude Code's sign-in.

The feature is off by default. Connecting it is the user's consent for CodexPill to sign in to Claude, or to read Claude Code's sign-in, and to send the token to Anthropic.

Claude usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

## Menu

A `Claude` section sits below the saved accounts and above `Cursor`. It has no switching actions. Each state has a short title and at most one line or one action.

- **Not connected.** `Connect Claude…`. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.**

  > **Sign in with Claude?**
  > CodexPill will open your browser to sign in to Claude and show your 5-hour and weekly limits. Your sign-in stays in your Keychain.

  Buttons `Sign In` and `Cancel`. Confirming first checks Claude Code's sign-in without any Keychain prompt. If it is there and unexpired, Claude connects at once and no browser opens. Otherwise the browser opens on Claude's sign-in page. The alert does not mention the Claude Code path, because knowing whether it applies would mean reading Claude Code's sign-in before consent.
- **Waiting for the browser.** `Finish signing in in your browser`, then `Cancel Sign-In`. After 5 minutes without an answer, or on cancel, the section goes back to where it was: `Connect Claude…` for a first sign-in. Claude counts as connected only once a sign-in succeeds.
- **Connected.** The choice is saved in user defaults (`claudeUsageEnabled`, off by default). `Preferences` gains `Disconnect Claude…`. It deletes CodexPill's Keychain item, asks Anthropic to revoke that sign-in, and turns the feature off, with no alert.
- **Current.** A caption with the read time (`As of 10:42`), plus the plan when the reading came from Claude Code's sign-in (`Max plan · As of 10:42`), then `Session` and `Weekly` meters with their reset times. The meters use the same percent mode, layout, colors, and pacing markers as the Codex card.
- **Waiting.** `Waiting for Claude usage`. Anthropic answered but sent neither window, for example on a plan without subscription limits.
- **Sign in again.** `Sign in to Claude again`, then `Sign In…`, which starts the browser sign-in at once. Shown when Anthropic rejects CodexPill's refresh token (`invalid_grant`) or the access token, or when there is no CodexPill sign-in and Claude Code's is missing or expired. Right after a rejection the last good values stay dimmed below. Once no sign-in is left at all, they are cleared.
- **Keychain access needed.** `Allow Keychain access…`. It reads again with the macOS Keychain prompt allowed. This can happen for either Keychain item, for example after Claude Code rewrites its item.
- **Read failed** (network, rate limit, unexpected response). `Can't reach Anthropic` / `Retrying in a few minutes.`, with the last good values dimmed below it and their `As of` time.
- **Stale.** A snapshot older than 15 minutes is dimmed. Its label still reads `As of …` until the next read.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting, signing in, `Allow Keychain access…`, and disconnecting read at once.

## Source Contract

All knowledge of Claude's OAuth, both sign-ins, and Anthropic's usage endpoint lives in `Sources/Platform/Claude`. Feature and UI code see parsed values only.

**Source order.** For each read:

1. CodexPill's own sign-in, refreshed first when it expires within 5 minutes.
2. Otherwise Claude Code's sign-in, only while it is unexpired.
3. Otherwise `Sign in to Claude again`.

**Sign in with Claude.** OAuth 2.0 authorization code with PKCE (S256), with the public client Claude Code uses. The values match Claude Code 2.1.294 and the CodexBar reference:

- Client id `9d1c250a-e61b-44d9-88ed-5944d1962f5e`.
- Authorize page `https://claude.com/cai/oauth/authorize` with `code=true`, `client_id`, `response_type=code`, `redirect_uri`, `scope=user:profile`, `code_challenge`, `code_challenge_method=S256`, and `state`, in that order. `user:profile` is the scope `api/oauth/usage` needs. CodexPill asks for nothing else.
- Redirect `http://localhost:<port>/callback`. A one-shot `NWListener` on the loopback interface, both IPv4 and IPv6, picks a free port. It answers the callback with a short "You can close this tab" page, answers any other path with `404`, and stops after the first callback.
- The callback must carry the `state` this sign-in sent, otherwise the code is never exchanged. `error=access_denied` ends the sign-in.
- Token endpoint `https://platform.claude.com/v1/oauth/token`, JSON bodies. Exchange: `grant_type=authorization_code`, `code`, `redirect_uri`, `client_id`, `code_verifier`, `state`. Refresh: `grant_type=refresh_token`, `refresh_token`, `client_id`, `scope`. The answer has `access_token`, `refresh_token`, and `expires_in` in seconds. A refresh that omits `refresh_token` keeps the current one.
- Revoke `https://platform.claude.com/v1/oauth/token/revoke` with `token`, `token_type_hint=refresh_token`, and `client_id`, best effort on disconnect.

**CodexPill's sign-in item.** A generic password in the login Keychain, service `CodexPill Claude sign-in`, account `Claude`, holding JSON with the access token, refresh token, and expiry. Never a file. One item means a rotated access and refresh token are saved in one write. Refreshes run one at a time: concurrent reads share one refresh, so a rotated refresh token is never spent twice. If the Keychain refuses to save a rotation, CodexPill keeps it in memory and retries the save on the next read.

**Claude Code's sign-in, read-only.** CodexPill looks in two places, in order, and never writes either:

1. `.credentials.json` in Claude Code's config folder: `CLAUDE_CONFIG_DIR` when CodexPill's environment sets it, otherwise `~/.claude`.
2. The login Keychain generic password with service `Claude Code-credentials` and account set to the macOS user name.

Both hold the same JSON. CodexPill decodes only `claudeAiOauth.accessToken`, `claudeAiOauth.expiresAt` (milliseconds since 1970), and `claudeAiOauth.subscriptionType`. It never decodes the refresh token. An item with no `claudeAiOauth`, for example one with only `mcpOAuth`, means signed out.

**Keychain prompts.** Only a user action may show the macOS Keychain prompt: finishing a sign-in or choosing `Allow Keychain access…`. Every other read of either item first checks that the item exists by asking for its attributes, which needs no decryption. It then asks for the data with an `LAContext` whose `interactionNotAllowed` is set and `kSecUseAuthenticationUI` set to skip. If macOS still needs approval, the read reports Keychain access needed instead of prompting. Background saves of a refreshed sign-in use the same no-interaction context.

**Usage request.** `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`.

**HTTP.** Every request that carries a token uses an ephemeral session with no cookie store and no URL cache. It follows a redirect only to the same host over HTTPS, so a token never reaches another host.

**Response.** `five_hour` and `seven_day` are each `{utilization, resets_at}`: `utilization` runs from 0 to 100 and `resets_at` is ISO 8601. CodexPill maps `five_hour` to `Session` (300 minutes) and `seven_day` to `Weekly` (10,080 minutes). It ignores other windows such as `seven_day_opus` and `seven_day_sonnet`. A null or missing window is left out. The plan name comes from Claude Code's `subscriptionType`, for example `max`. CodexPill's own sign-in has no plan name.

## Read Policy

- CodexPill's sign-in within 5 minutes of expiry: refresh first. `invalid_grant` deletes the item and shows sign in again. A network failure keeps using the current access token until it expires, then shows read failed.
- Claude Code's expired token (`expiresAt` in the past): no request. Sign in again.
- `401` from the usage endpoint: sign in again.
- `429`: no request until `Retry-After` seconds pass, or 5 minutes when the header is missing or not a number. The menu shows read failed meanwhile.
- Network failure, another status, or an unreadable body: read failed. The shared provider runtime keeps the last good values.
- No token is ever logged, printed, or displayed. `ClaudeAccessToken`, `ClaudeRefreshToken`, and `ClaudePKCE` print as `<Type>(redacted)` and reflect no children.

## Isolated Runs

With `CODEXPILL_VALIDATION_APP_SUPPORT_DIR` set, CodexPill never reads a real Claude sign-in, opens a browser or a port, or calls Anthropic:

- Claude Code's config folder is `CLAUDE_CONFIG_DIR` when set, otherwise `<root>/.claude`. Its Keychain item is `<root>/claude-keychain-item.json`. A background read reports Keychain access needed until one read allows the prompt.
- CodexPill's own sign-in item is `<root>/claude-sign-in-item.json`.
- The browser sign-in writes the authorize URL to `<root>/claude-authorize-url.txt` and waits for a request line such as `GET /callback?code=…&state=… HTTP/1.1` in `<root>/claude-browser-callback.txt`. The real `state` check applies.
- Every token request answers with `<root>/claude-token-response.json`. A missing file reads as a network failure, and a body with `invalid_grant` as a rejected sign-in.
- The usage response is read from `<root>/claude-usage-response.json`. A missing file reads as a network failure.
- `CODEXPILL_VALIDATION_AUTO_REFRESH_INTERVAL_SECONDS` also shortens the Claude read interval.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `ClaudeOAuthTests` check the PKCE challenge against RFC 7636's example, the exact authorize URL for a fixed state and verifier, callback request-line parsing, `state` mismatch rejection, token response parsing, `invalid_grant` mapping, the token request bodies, the refresh-before-expiry rule, and that no token appears when a sign-in or its requests are printed.
- `ClaudeBrowserSignInTests` run the flow with a stub redirect: the matching callback is exchanged, a forged `state` is never exchanged, and a missing callback times out. One test runs the real loopback listener over `127.0.0.1` and `::1`.
- `ClaudeCredentialsTests` parse literal Claude Code credentials, including the `mcpOAuth`-only case, prove the file wins over the Keychain, and prove the token appears in no printed output.
- `ClaudeUsageAPITests` cover the usage response mapping, the request headers, the redirect rule, and status mapping for `401` and `429`.
- `ClaudeCodeUsageTests` cover the source order, connecting with a fresh Claude Code sign-in, a cancelled first sign-in, refresh and rotation, `invalid_grant`, a refresh that cannot reach Anthropic, one shared refresh for two reads, disconnect, the Keychain prompt only after a user action, and the rate-limit wait.
- Two coordinator tests walk the built `NSMenu`: consent, waiting with `Cancel Sign-In`, current usage, `Sign in to Claude again` with `Sign In…`, disconnect, and `Allow Keychain access…`.
- No test touches Anthropic or a real Keychain item.
