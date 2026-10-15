# Claude Usage

## User Story

As a Refill user who also works in Claude Code on a Pro or Max plan, I want to see my Claude 5-hour and weekly limits next to my Codex limits, so I can pick the tool with headroom without opening Claude Code's `/usage` screen.

## Product Contract

Claude Usage is an optional menu bar feature. When connected, Refill shows the 5-hour and weekly limits of the Claude account that Claude Code is signed in to, or of the account the user signed in to with Refill's own `Sign in with Claude…`.

Reading usage never changes anything in Claude Code. Refill never renews Claude Code's sign-in, never sends its refresh token, and never runs `claude`. If Claude Code's sign-in is missing or expired, Refill says so and points the user back to Claude Code or to Refill's own sign-in, as [No Renewal](#no-renewal) explains. Refill shows one account at a time, by its email. It never saves, adds, or switches Claude accounts, and it never writes Claude Code's files or Keychain item.

Refill's own sign-in is opt-in. It exists for the Claude desktop app, whose Claude Code gets its token injected and never renews the Keychain item Refill reads, so the card would stay expired. See [Refill's Own Sign-In](#refills-own-sign-in).

The feature is off by default. Connecting it is the user's consent for Refill to read Claude Code's sign-in and send it to Anthropic.

Claude usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

Refill never reads or writes Claude Code's `settings.json`. Reading limits from Anthropic, rather than from Claude Code's status line, means usage stays current when Claude Code runs in the Claude desktop app or remotely.

## Menu

The `Claude` card follows the shared card and side menu in [Menubar](menubar.md). The side menu shows the signed-in email, checked and disabled, then `Sign in with Claude…` while Refill's own sign-in is off or `Sign Out of Claude` while it is on, then the model limit toggle and the moves. It has no other account actions. `Appearance › Show Tools › Claude` disconnects it.

- **Not connected.** There is no card. Checking `Appearance › Show Tools › Claude` connects. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Claude Code?**
  > Uses Claude Code's sign-in to read your limits.

  Confirming saves the choice and reads at once.
- **Connected.** The choice is saved in user defaults (`claudeUsageEnabled`, off by default). Unchecking `Appearance › Show Tools › Claude` turns the feature off at once with no alert, because it changes nothing outside Refill. Checking it again connects through the same consent alert.
- **Current.** The plan tag (`Max x20`, read from `organizationRateLimitTier`, else `userRateLimitTier`, in Claude Code's `oauthAccount`, because the credentials' `rateLimitTier` keeps the tier from sign-in time; that one is used only when the account record has none), then `Session` and `Weekly` meters with their reset times, then one meter per model with its own weekly limit, such as `Fable this week`, unless the side menu's model limit toggle is off. When extra usage is on, one line follows: `$12.40 of $50.00 extra usage`, or `$12.40 extra usage` with no monthly limit. There is no reset-credit row. The meters use the same percent mode, layout, colors, and pacing markers as the Codex card.
- **Waiting.** `Waiting for Claude Code usage`, with no second line. Anthropic answered but sent neither window, for example on a plan without subscription limits.
- **Sign in with Claude.** Under the card, `Sign in with Claude…` appears while Claude Code is signed out or its sign-in expired, and while Refill's own sign-in needs a new sign-in. It and the side menu item open one short alert first:

  > **Sign in with Claude?**
  > Opens your browser. Refill keeps this sign-in in its own Keychain item.

  `Sign In` opens the browser. A second `Sign in with Claude…` cancels the first and starts again, in case the tab was closed. Success connects Claude, switches reads to Refill's own sign-in, and reads at once. A declined, timed out or failed sign-in shows one info alert and changes nothing. A cancelled one shows none.
- **Keychain access needed.** `security` was refused or timed out, for example on a locked Keychain. With an earlier reading, the card keeps it dimmed under its `As of` time. Without one, it says `Allow Keychain access`. Either way, one row under it, `Allow Keychain Access…`, reads again and waits up to 2 minutes so the user can answer a macOS prompt.
- **Failures.** Each failure shows a title and one short line. Except for signed out and sign in again, the last good values stay dimmed below it with their `As of` time. A new sign-in may be another account.

  | Cause | Title | Second line |
  |---|---|---|
  | No sign-in | `Not signed in to Claude Code` | `Run claude, then /login.` |
  | Token past its expiry, or `401` | `Claude Code sign-in expired` | `Run claude, or sign in with Claude.` |
  | Refill's own sign-in gone, rejected, or `401` after one renewal | `Sign in to Claude again` | none |
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

**Extra usage.** `extra_usage` is `{is_enabled, used_credits, monthly_limit, currency, decimal_places}`. Amounts are in minor units: Refill divides them by 10 to the power `decimal_places` (2 when null). A null or empty `currency` reads as USD. Refill shows it only when `is_enabled` is true and `used_credits` is set, and `monthly_limit` is optional. A disabled or unreadable `extra_usage` shows nothing and never fails the read. Refill ignores the `spend` object and codename keys.

## Refill's Own Sign-In

**Source order.** `claudeUsesOwnSignIn` in user defaults picks the sign-in. While it is on, reads use Refill's own sign-in only. When that is missing or rejected, the card says `Sign in to Claude again`. It never falls back to Claude Code's sign-in, which may be another account. While it is off, reads use Claude Code's sign-in exactly as [Source Contract](#source-contract) describes. A browser sign-in that succeeds turns it on, even when the Keychain refused to save the sign-in. `Sign Out of Claude` and disconnecting turn it off.

**Sign-in.** OAuth 2.0 authorization code with PKCE (S256), the flow and public client Claude Code uses (client ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e`). The browser opens `https://claude.com/cai/oauth/authorize` with scope `user:profile`, a random `state`, and a redirect to `http://localhost:<port>/callback` on a listener bound to the loopback interface. A callback with another `state` is refused. Refill trades the code at `https://platform.claude.com/v1/oauth/token`, reads the email from `account.email_address` if present, then reads `GET https://api.anthropic.com/api/oauth/profile` once for the plan (`organization.organization_type` with the `NNx` suffix of `organization.rate_limit_tier`, such as `max_20x`) and the email as a fallback. A failed profile read never fails the sign-in. The sign-in times out after 5 minutes.

**Storage.** One generic password, service `Refill Claude sign-in`, account `Claude`, readable after first unlock. Its JSON holds both tokens, the expiry, the email, the plan, and `refreshPending`. Refill creates it, so Refill reads it without a prompt. A background read never allows a prompt. If the Keychain refuses the save, the sign-in lasts until Refill quits, with the info alert `Claude sign-in not saved`.

**Safe renewal.** Claude rotates the refresh token on every refresh and accepts each one once. On 2026-10-15 a refresh token spent without being saved logged Claude Code out. Refill's renewal makes that impossible for its own sign-in:

1. A read renews the token when it expires within 5 minutes. Renewals run one at a time in the process and, through a `flock` on `claude-sign-in.lock` in Application Support, one at a time across Refill processes. A lock held for 30 seconds reads as unreachable and is tried again later.
2. Under the lock, Refill reads the item again. If another process already renewed it, Refill uses the new token. If the item is still marked `refreshPending`, a renewal never saved its result and its refresh token is presumed spent: Refill deletes the item and asks for a new sign-in without sending it.
3. Refill saves the item with `refreshPending` set. If that save fails, nothing is sent.
4. Refill sends the refresh token. On success it saves the new pair with the mark cleared, retrying once. A pair it could not save stays in memory, wins over the Keychain, and is saved on the next read.
5. `invalid_grant` deletes only Refill's item. A network failure, another refusal, or an unreadable reply clears the mark, keeps the tokens, and uses the current token while it is unexpired.

A `401` on the usage request gets exactly one renewal and one retry, unless another process already renewed the token. A second `401` asks for a new sign-in.

**Sign-out.** `Sign Out of Claude`, or disconnecting, deletes the item under the lock, then asks `https://platform.claude.com/v1/oauth/token/revoke` to revoke the refresh token, best effort. Reads go back to Claude Code's sign-in. If the item can't be deleted, one info alert says `Claude sign-in not removed`.

**Logging.** `ClaudeSignIn` log lines carry a fixed category only: attempt, ok, invalid_grant, network, rejected, malformed, save_failed, unfinished, busy, and whether a sign-in was saved or removed.

## Token Usage

When Token Usage is also on, the Token Usage card adds Claude Code's daily tokens by model from its local transcripts. That read uses no sign-in and no network. See [Token Usage](token-usage.md#other-tools).

## Read Policy

- Expired token (`expiresAt` in the past): no request. The menu shows sign-in expired until Claude Code renews it (see [No Renewal](#no-renewal)).
- `401`: sign-in expired.
- `403`: access denied. Anthropic knows the token but won't share usage with it, for example a token without the profile scope.
- `429`: no request until `Retry-After` passes, given as seconds or an HTTP date, or 5 minutes when the header is missing or unreadable. The menu shows rate limited meanwhile.
- Network failure: unreachable. Another status: service error. An unreadable body: unexpected response. The shared provider runtime keeps the last good values for all of these.
- Refill holds Claude Code's token only for the length of one read. It never stores, logs, displays, or refreshes it. `ClaudeAccessToken` prints as `ClaudeAccessToken(redacted)` and reflects no children.

## No Renewal

Claude Code's access token lasts 8 hours, and Claude Code renews it only while it runs. Refill never renews it and never starts `claude` to make Claude Code do it. Running `claude` in a terminal renews it, and the next read picks up the new token. Refill's own sign-in is the alternative when Claude Code never renews it, as in the Claude desktop app.

A test build once ran `claude doctor` in the background to renew an expired sign-in. That logged Claude Code out on 2026-10-15. `doctor` renews the token only as a side effect and can exit before it saves the renewed token. A later run then sends the used refresh token, Anthropic answers `invalid_grant`, and Claude Code clears both tokens. Claude Code has no command that renews a sign-in safely without a terminal, so Refill does not try.

Refill logs when a tool's sign-in becomes expired or signed out, with the category only.

## Isolated Runs

With `REFILL_ISOLATED_APP_SUPPORT_DIR` set, Refill never reads the real Claude sign-in:

- The config folder is `CLAUDE_CONFIG_DIR` when set, otherwise `<root>/.claude`. Only its `.credentials.json` and `.claude.json` are read.
- The Keychain is skipped, so a missing file reads as signed out. An expired sign-in in that file shows the sign-in expired state without any request.
- Refill's own sign-in lives in `<root>/claude-sign-in.json` (0600, written atomically) instead of its Keychain item, with its lock in `<root>/claude-sign-in.lock`. `Sign in with Claude…` still opens the browser and a loopback port.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `ClaudeCredentialsTests` parse literal credentials, including the `mcpOAuth`-only case, prove the file wins over the Keychain, and prove the token appears in no `String(describing:)`, `String(reflecting:)`, or `dump` output of the credentials or the request.
- `ClaudeUsageAPITests` cover the response mapping, the request headers, the redirect rule, and status mapping for `401` and `429`. `RetryAfterTests` cover the shared `Retry-After` parser.
- `ClaudeCodeUsageTests` cover opt-in, the Keychain prompt only after a user action, the expiry gate, each failure state, and the rate-limit wait. A scan in `ClaudeCredentialsTests` proves that only the files of Refill's own sign-in use a refresh token and that none of them names Claude Code's sign-in, and other `ClaudeCredentialsTests` read the plan tier and the email from the account record.
- `ClaudeLiveSignInTests` run the provider runtime over a temp sign-in: an expired one stays expired over an hour of reads and sends no token, one Claude Code renewed is read on the next refresh, and one Claude Code cleared shows signed out.
- `ProviderCopyTests` checks that every failure reads differently and stays a title plus one short line.
- `ClaudeOAuthTests` and `ClaudeBrowserSignInTests` cover the RFC 7636 PKCE vector, the authorize URL, callback parsing, the `state` check, token parsing, the timeout, and the loopback listener. `ClaudeSignInStoreTests` and `ClaudeRefreshLockTests` cover the stored item with its marker and the lock.
- `ClaudeOwnSignInTests` prove that a renewal that never saved its result is not retried on the next launch, that two processes renewing at once send the refresh token once, that a failed renewal keeps the token, and that sign-out deletes and revokes.
- `ClaudeOwnSignInUsageTests` check the order mark, refresh, save, usage, a refused save retried without a second refresh, `invalid_grant` never falling back to Claude Code's sign-in, the one renewal after a `401`, and sign-in, sign-out and disconnect.
- `ToolSectionTests` and `MenuBarMenuBuilderTests` check `Sign in with Claude…` under the card and in the side menu, and `Sign Out of Claude`. A coordinator test checks the sign-in alert and the notice after a failed sign-in.
- `ClaudeCodeSecurityKeychainTests` check the `security` arguments and timeouts, text and hex passwords, and that each exit status reads as signed out, access needed or unreadable.
- `UsageReadFailureTests` check that a failed read logs only its category, such as `http 503`.
- A coordinator test walks the menu from `Appearance › Show Tools › Claude` through declined consent, current usage, `Allow Keychain Access…`, and disconnect, reading the built `NSMenu`.
- No test touches the network or the real Keychain. Refill's own sign-in uses temp files and fake tokens.
