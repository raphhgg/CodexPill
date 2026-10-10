# Privacy And Data Handling

CodexPill is a local macOS menubar utility for Codex account switching and limit visibility. It can also show Claude Code and Cursor usage if you connect them, and switch Claude Code or Cursor between sign-ins you saved. Its most sensitive data is Codex authentication state. Treat saved account snapshots as secrets.

## What CodexPill Reads

During normal use, CodexPill may read:

- `~/.codex/auth.json` to identify and save the currently active Codex account.
- Codex account metadata exposed by Codex, such as email address, plan type, account identity, rate-limit windows, and limit reset credits.
- Local Codex app-server status to refresh account and limit information.
- Local process information to detect running Codex CLI sessions when a switch may require a restart or user action.
- CodexPill-owned state under `~/Library/Application Support/CodexPill`.
- Claude Code's sign-in, from `~/.claude/.credentials.json` or the `Claude Code-credentials` Keychain item, while Claude Code usage is connected with it or when you save or switch a Claude Code account. See [Claude Code](#claude-code).
- CodexPill's own Claude sign-in, from its `CodexPill Claude sign-in` Keychain item, while Claude usage is connected with it.
- Local process information to detect a running Claude Code before switching Claude Code accounts.
- Cursor's access token from Cursor's local database, while Cursor usage is connected, and Cursor's sign-in rows from the same database when you save or switch a Cursor account. See [Cursor](#cursor).

## What CodexPill Writes Or Stores

CodexPill writes and stores:

- A local account catalog under `~/Library/Application Support/CodexPill`.
- Saved Codex auth snapshots under `~/Library/Application Support/CodexPill/snapshots`.
- `~/.codex/auth.json` when switching the active local Codex account.
- Temporary isolated `CODEX_HOME` state when capturing a new Codex sign-in without mutating the current account.
- Saved Claude Code accounts in `CodexPill Claude Code account` Keychain items and `claude-code-accounts.json`, and Claude Code's own sign-in when you switch Claude Code accounts. See [Claude Code](#claude-code).
- Saved Cursor accounts in one `CodexPill Cursor accounts` Keychain item, and Cursor's sign-in rows in its local database when you switch Cursor accounts. See [Cursor](#cursor).
- CodexPill's own Claude sign-in, after you choose "Sign in with Claude": one login Keychain generic password, service `CodexPill Claude sign-in`, account `Claude`, holding its access token, refresh token, and expiry. Never a file. Disconnecting deletes it.

Saved auth snapshots contain authentication material and must be handled like credentials. They should not be printed, logged, attached to issues, or committed to git.

## Codex Auth Stays On This Mac

CodexPill never copies Codex auth snapshots or Codex tokens to another machine or service. Earlier versions could copy a selected snapshot to an SSH host you configured. That feature is gone. [Uninstall And Reset](UNINSTALL_RESET.md) explains how to remove what it left on a host.

## Claude Code

CodexPill never asks Anthropic for a new Claude Code token, and never reads, sends, or renews Claude Code's refresh token. It refreshes only its own sign-in.

**Usage (optional, off by default).** `Settings › Add Account › Claude…` asks for consent before anything is read. Claude usage then reads with exactly one sign-in, and never falls back to the other:

- **Claude Code's sign-in**, when it is there and unexpired. Each read reads `.credentials.json` in Claude Code's config folder (`CLAUDE_CONFIG_DIR`, or `~/.claude`), and if that file holds no Claude sign-in, the login Keychain generic password with service `Claude Code-credentials` and your macOS user name as the account. It uses only the access token, its expiry, and the plan name.
- **CodexPill's own sign-in**, otherwise. CodexPill opens your browser on `claude.com` to sign in, with OAuth and PKCE. Claude sends the browser back to a one-time listener on `http://localhost:<port>/callback`, on a free port the system picks, that accepts loopback connections only and stops after one callback. CodexPill exchanges the code at `platform.claude.com`, saves the result in its Keychain item, and refreshes it there shortly before it expires or once after Anthropic rejects it.

Each read sends one access token to `GET https://api.anthropic.com/api/oauth/usage` to fetch your 5-hour and weekly limits. CodexPill's own sign-in also talks to `https://platform.claude.com/v1/oauth/token` (code exchange and refresh) and `https://platform.claude.com/v1/oauth/token/revoke` (on disconnect). Redirects to any other host, or to plain HTTP, are refused. These requests have no cookies and no cache. CodexPill asks only for the `user:profile` scope.

macOS may ask you to allow Keychain access. CodexPill shows that prompt only right after you connect, finish a sign-in, or choose `Allow Keychain access…`. CodexPill never logs or displays a token, and it never reads browser cookies or Claude conversations. `Disconnect Claude` turns usage off, stops all reads, deletes CodexPill's own Claude sign-in, and asks Anthropic to revoke it.

**Saved Claude Code accounts.** CodexPill can save Claude Code sign-ins and switch between them. Only a user action does this; nothing runs in the background. Saving one:

- reads Claude Code's sign-in as above, and `oauthAccount` from Claude Code's global config (`$CLAUDE_CONFIG_DIR/.claude.json`, or `~/.claude.json`);
- writes a copy of the `claudeAiOauth` and `oauthAccount` objects to a login Keychain item CodexPill owns, service `CodexPill Claude Code account`, one item per saved account, with the account's CodexPill ID as the Keychain account;
- writes the account's name, email, organization name, plan, and Claude account IDs, but no tokens, to `~/Library/Application Support/CodexPill/claude-code-accounts.json`.

Switching also writes Claude Code's own sign-in:

- it updates the existing `Claude Code-credentials` Keychain item, or `.credentials.json` when the sign-in lives there. Only `claudeAiOauth` changes; other keys, such as MCP sign-ins, stay as they were. CodexPill never creates or deletes Claude Code's Keychain item;
- it replaces `oauthAccount` in Claude Code's global config and keeps every other key;
- it reads the process table first and refuses to switch while any `claude` process runs, including Claude Code inside the Claude desktop app.

If any step fails, CodexPill puts back every file and item it had already changed.

## Cursor

CodexPill never signs in to Cursor, never asks Cursor for a new token, and never sends Cursor's refresh token anywhere. It only uses the sign-in Cursor already has. Cursor keeps it in a SQLite database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, and CodexPill reads it only by key, never by scanning.

**Usage (optional, off by default).** `Settings › Add Account › Cursor…` asks for consent before anything is read. While it is connected, each read:

- opens that database read-only and reads one row, `cursorAuth/accessToken`. When Cursor is closed, the database is opened so that no file is created next to it; when Cursor has it open, SQLite reads only committed data;
- uses the token only while it is more than a minute from expiry;
- sends the token to one place, `GET https://cursor.com/api/usage-summary`, as Cursor's session cookie, to fetch your plan usage, on-demand spend, and billing cycle. Redirects are refused, and the request has no cookie store and no cache. After a `429`, nothing is read or sent until cursor.com's `Retry-After` passes.

CodexPill never stores, logs, or displays the token, and it never reads browser cookies or Cursor projects. `Disconnect Cursor` turns usage off and stops all reads.

**Saved Cursor accounts.** CodexPill can save Cursor sign-ins and switch between them. Only a user action does this; nothing runs in the background, and switching makes no network call. Saving one copies the eight `cursorAuth/*` rows that are a Cursor sign-in (`accessToken`, `refreshToken`, `cachedEmail`, `cachedScopedProfile`, `cachedSignUpType`, `stripeMembershipAuthId`, `stripeMembershipType`, `stripeSubscriptionStatus`) into one login Keychain item CodexPill owns, service `CodexPill Cursor accounts`, with the name you give it. Those rows include Cursor's tokens and your Cursor email. Nothing about them goes to a file.

Switching quits and changes Cursor:

- it asks Cursor to quit and waits for it to exit. It never force-quits, so Cursor can ask about unsaved work. If Cursor is still running, nothing is written;
- it refuses to write while any other process still holds the database;
- it saves the outgoing sign-in again, because Cursor may have renewed its tokens, then writes the chosen account's eight rows into `state.vscdb` in one transaction. No other row and no other Cursor file changes;
- it opens Cursor again. If a step fails after Cursor quit, the database is left as it was and Cursor reopens on the sign-in it had.

Removing a saved account deletes it from CodexPill's Keychain item only. Cursor stays signed in as it is.

## What CodexPill Does Not Require By Default

Normal CodexPill usage does not require:

- browser cookies;
- hidden browser windows or hidden WebViews;
- ChatGPT web dashboard scraping;
- Full Disk Access;
- Screen Recording;
- Accessibility permissions.

Accessibility may still be useful for development or validation tooling that inspects native UI, but it is not a product requirement for normal account switching or limit monitoring.

## Network And External Services

CodexPill talks to Codex through local Codex surfaces. When Claude usage is on, it also calls api.anthropic.com with Claude Code's sign-in token or CodexPill's own, and CodexPill's own sign-in calls claude.com in your browser and platform.claude.com for its tokens. When Cursor usage is on, it calls cursor.com with Cursor's own sign-in token. Switching Claude Code or Cursor accounts makes no network call. It must not send Codex auth snapshots, raw auth payloads, or tokens to analytics services, crash-reporting systems, issue trackers, or any other third-party API. A token may go only to the service that issued it.

If future features add status-page checks, diagnostics export, or usage statistics, they must keep the same rule: aggregate or redact data before it leaves the machine, and never include raw auth payloads or tokens.

## Logging And Diagnostics

Logs and diagnostics may include high-level workflow events, rate-limit percentages, and error categories. Account identifiers, host names, and local paths should be treated as private by default in support artifacts. Logs and diagnostics must not include raw auth snapshots, token values, API keys, or complete auth payloads.

When sharing logs for debugging, review them first and redact account identifiers, host names, or paths when needed.

CodexPill's user-initiated diagnostic report export is a redacted JSON support artifact. It uses per-export aliases for accounts, summarizes freshness and result categories, and includes a manifest of omitted, summarized, and rejected field classes. The export must be built from allowlisted fields and must not include raw logs, raw auth JSON, saved snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, refresh tokens, stable account IDs, prompt/session content, or raw stderr.
