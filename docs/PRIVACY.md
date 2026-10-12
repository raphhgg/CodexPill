# Privacy And Data Handling

CodexPill is a local macOS menubar utility for Codex account switching and limit visibility. It can also show Claude Code and Cursor usage if you connect them. For those two tools it only reads: it never writes their files or Keychain items. Its most sensitive data is Codex authentication state. Treat saved account snapshots as secrets.

## What CodexPill Reads

During normal use, CodexPill may read:

- `~/.codex/auth.json` to identify and save the currently active Codex account.
- Codex account metadata exposed by Codex, such as email address, plan type, account identity, rate-limit windows, and limit reset credits.
- Local Codex app-server status to refresh account and limit information.
- Local process information to detect running Codex CLI sessions when a switch may require a restart or user action.
- CodexPill-owned state under `~/Library/Application Support/CodexPill`.
- Claude Code's sign-in, from `~/.claude/.credentials.json` or the `Claude Code-credentials` Keychain item, while Claude Code usage is connected. See [Claude Code](#claude-code).
- Cursor's access token from Cursor's local database, while Cursor usage is connected. See [Cursor](#cursor).

## What CodexPill Writes Or Stores

CodexPill writes and stores:

- A local account catalog under `~/Library/Application Support/CodexPill`.
- Saved Codex auth snapshots under `~/Library/Application Support/CodexPill/snapshots`.
- `~/.codex/auth.json` when switching the active local Codex account.
- Temporary isolated `CODEX_HOME` state when capturing a new Codex sign-in without mutating the current account.

Saved auth snapshots contain authentication material and must be handled like credentials. They should not be printed, logged, attached to issues, or committed to git.

## Codex Auth Stays On This Mac

CodexPill never copies Codex auth snapshots or Codex tokens to another machine or service. Earlier versions could copy a selected snapshot to an SSH host you configured. That feature is gone. [Uninstall And Reset](UNINSTALL_RESET.md) explains how to remove what it left on a host.

## Claude Code

CodexPill never signs in to Claude, never asks Anthropic for a new token, and never reads, sends, or renews Claude Code's refresh token. It only uses the sign-in Claude Code already has.

**Usage (optional, off by default).** `Connect Claude Code…` asks for consent before anything is read. While it is connected, each read:

- reads `.credentials.json` in Claude Code's config folder (`CLAUDE_CONFIG_DIR`, or `~/.claude`), and if that file holds no Claude sign-in, the login Keychain generic password with service `Claude Code-credentials` and your macOS user name as the account;
- uses only the access token, its expiry, and the plan name from that sign-in;
- sends the access token to one place, `GET https://api.anthropic.com/api/oauth/usage`, to fetch your 5-hour and weekly limits. Redirects to any other host, or to plain HTTP, are refused. The request has no cookies and no cache.

macOS may ask you to allow Keychain access. CodexPill shows that prompt only right after you connect or choose `Allow Keychain access…`. CodexPill never stores, logs, or displays the token, and it never reads browser cookies or Claude conversations. `Disconnect Claude Code…` turns usage off and stops all reads.

## Cursor

CodexPill never signs in to Cursor, never asks Cursor for a new token, and never sends Cursor's refresh token anywhere. It only uses the sign-in Cursor already has. Cursor keeps it in a SQLite database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, and CodexPill reads it only by key, never by scanning.

**Usage (optional, off by default).** `Connect Cursor…` asks for consent before anything is read. While it is connected, each read:

- opens that database read-only and reads one row, `cursorAuth/accessToken`. When Cursor is closed, the database is opened so that no file is created next to it; when Cursor has it open, SQLite reads only committed data;
- uses the token only while it is more than a minute from expiry;
- sends the token to one place, `GET https://cursor.com/api/usage-summary`, as Cursor's session cookie, to fetch your plan usage, on-demand spend, and billing cycle. Redirects are refused, and the request has no cookie store and no cache. After a `429`, nothing is read or sent until cursor.com's `Retry-After` passes.

CodexPill never stores, logs, or displays the token, and it never reads browser cookies or Cursor projects. `Disconnect Cursor…` turns usage off and stops all reads.

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

CodexPill talks to Codex through local Codex surfaces. When Claude Code usage is on, it also calls api.anthropic.com with Claude Code's own sign-in token. When Cursor usage is on, it calls cursor.com with Cursor's own sign-in token. It must not send Codex auth snapshots, raw auth payloads, or tokens to analytics services, crash-reporting systems, issue trackers, or any other third-party API. A token may go only to the service that issued it.

If future features add status-page checks, diagnostics export, or usage statistics, they must keep the same rule: aggregate or redact data before it leaves the machine, and never include raw auth payloads or tokens.

## Logging And Diagnostics

Logs and diagnostics may include high-level workflow events, rate-limit percentages, and error categories. Account identifiers, host names, and local paths should be treated as private by default in support artifacts. Logs and diagnostics must not include raw auth snapshots, token values, API keys, or complete auth payloads.

When sharing logs for debugging, review them first and redact account identifiers, host names, or paths when needed.

CodexPill's user-initiated diagnostic report export is a redacted JSON support artifact. It uses per-export aliases for accounts, summarizes freshness and result categories, and includes a manifest of omitted, summarized, and rejected field classes. The export must be built from allowlisted fields and must not include raw logs, raw auth JSON, saved snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, refresh tokens, stable account IDs, prompt/session content, or raw stderr.
