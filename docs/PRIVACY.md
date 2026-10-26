# Privacy And Data Handling

rusage is a local macOS menubar utility for Codex account switching and limit visibility. It can also show Claude Code and Cursor usage if you connect them. For those two tools it only reads. It never writes their files or Keychain items, and it never runs them. For Claude you can also opt in to rusage's own sign-in, which rusage keeps apart from Claude Code's. Its most sensitive data is Codex authentication state. Treat saved account snapshots as secrets.

rusage was called CodexPill before. On its first launch rusage copies CodexPill's saved Codex accounts and settings into its own folder and preferences, unless rusage already has data. It does not copy Claude or Cursor accounts a test build may have saved. It never changes or deletes CodexPill's copies. [Uninstall And Reset](UNINSTALL_RESET.md) explains how to remove them.

## What rusage Reads

During normal use, rusage may read:

- `~/.codex/auth.json` to identify and save the currently active Codex account.
- Codex account metadata exposed by Codex, such as email address, plan type, account identity, rate-limit windows, credit balance, and limit reset credits.
- Local Codex app-server status to refresh account and limit information.
- Local process information to detect running Codex CLI sessions when a switch may require a restart or user action.
- rusage-owned state under `~/Library/Application Support/rusage`.
- Claude Code's sign-in, from `~/.claude/.credentials.json` or the `Claude Code-credentials` Keychain item, while Claude Code usage is connected. See [Claude Code](#claude-code).
- Cursor's access token and cached email from Cursor's local database, while Cursor usage is connected. See [Cursor](#cursor).

## What rusage Writes Or Stores

rusage writes and stores:

- A local account catalog under `~/Library/Application Support/rusage`, with each account's last limits, credit balance, and reset credits.
- Saved Codex auth snapshots under `~/Library/Application Support/rusage/snapshots`.
- `~/.codex/auth.json` when switching the active local Codex account.
- Temporary isolated `CODEX_HOME` state when capturing a new Codex sign-in without mutating the current account.
- rusage's own Claude sign-in, only after you choose `Sign in with Claude…`, in the login Keychain item `rusage Claude sign-in`, and an empty lock file, `claude-sign-in.lock`, under `~/Library/Application Support/rusage`. See [rusage's own Claude sign-in](#rusages-own-claude-sign-in).

Saved auth snapshots contain authentication material and must be handled like credentials. They should not be printed, logged, attached to issues, or committed to git.

## Codex Auth Stays On This Mac

rusage never copies Codex auth snapshots or Codex tokens to another machine or service. Earlier versions could copy a selected snapshot to an SSH host you configured. That feature is gone. [Uninstall And Reset](UNINSTALL_RESET.md) explains how to remove what it left on a host.

## Claude Code

rusage never reads, sends, or renews Claude Code's refresh token, and it never writes Claude Code's files or Keychain item. Unless you sign in with rusage's own sign-in, it only uses the sign-in Claude Code already has.

**Usage (optional, off by default).** Turning on `Settings › Tools › Claude` asks for consent before anything is read. While it is connected, each read:

- reads `.credentials.json` in Claude Code's config folder (`CLAUDE_CONFIG_DIR`, or `~/.claude`), and if that file holds no Claude sign-in, the login Keychain generic password with service `Claude Code-credentials` and your macOS user name as the account. rusage reads that item by running `/usr/bin/security find-generic-password -w`, the same command Claude Code uses. Claude Code creates the item with `security`, so `security` can read it without a prompt. The password comes back through a pipe and is never logged;
- uses only the access token, its expiry, and the plan name from that sign-in;
- reads the plan tier and your email from `oauthAccount` in Claude Code's global config (`$CLAUDE_CONFIG_DIR/.claude.json`, or `~/.claude.json`). The email shows in the Claude side menu, masked with Hide Emails;
- sends the access token to one place, `GET https://api.anthropic.com/api/oauth/usage`, to fetch your 5-hour and weekly limits and any extra usage. Redirects to any other host, or to plain HTTP, are refused. The request has no cookies and no cache.

If macOS refuses `security` access, for example while the Keychain is locked, the card keeps the last limits and offers `Allow Keychain Access…`. That retry gives you time to answer a macOS prompt. rusage never stores, logs, or displays the token, and it never reads browser cookies or Claude conversations. Turning off `Settings › Tools › Claude` turns usage off and stops all reads.

**No renewal.** rusage never starts `claude`. When Claude Code's token expires, the card says so until you run `claude`, which renews it, or you sign in with rusage's own sign-in. A background renewal could log Claude Code out, so rusage leaves Claude Code's sign-in to you.

### rusage's own Claude sign-in

This is optional and off until you choose `Sign in with Claude…` and confirm. It helps when Claude Code runs inside the Claude desktop app, which never renews the sign-in rusage reads.

- Your browser opens claude.com to approve the sign-in. Claude sends a one-time code back to a listener on this Mac only (`http://localhost:<port>/callback`), and rusage trades it at platform.claude.com for an access token and a refresh token.
- rusage keeps both tokens, their expiry, your email and your plan only in its own login Keychain item, `rusage Claude sign-in`. It never writes them to a file or a log, and it never touches Claude Code's `Claude Code-credentials` item.
- The tokens go only to platform.claude.com, to sign in, renew and revoke, and to api.anthropic.com, to read your limits and, once after signing in, your plan and email from `/api/oauth/profile`.
- While you are signed in this way, rusage reads limits with this sign-in only. If it stops working, the card asks you to sign in again. rusage never falls back to Claude Code's sign-in, which may be another account.
- rusage renews the access token shortly before it expires. Before it sends a refresh token, it marks the Keychain item, and it clears the mark when it saves the new tokens. If rusage quits in between, it deletes the item at the next launch and asks you to sign in again, instead of sending a refresh token that may already be spent. A lock file, `claude-sign-in.lock`, keeps two copies of rusage from renewing at once.
- `Sign Out of Claude` and turning off `Settings › Tools › Claude` delete the item and ask Anthropic to revoke the refresh token.

## Cursor

rusage never signs in to Cursor, never asks Cursor for a new token, and never sends Cursor's refresh token anywhere. It only uses the sign-in Cursor already has. Cursor keeps it in a SQLite database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, and rusage reads it only by key, never by scanning.

**Usage (optional, off by default).** Turning on `Settings › Tools › Cursor` asks for consent before anything is read. While it is connected, each read:

- opens that database read-only and reads two rows, `cursorAuth/accessToken` and `cursorAuth/cachedEmail`. The email shows in the Cursor side menu, masked with Hide Emails. When Cursor is closed, the database is opened so that no file is created next to it; when Cursor has it open, SQLite reads only committed data;
- uses the token only while it is more than a minute from expiry;
- sends the token to one place, `GET https://cursor.com/api/usage-summary`, as Cursor's session cookie, to fetch your plan usage, on-demand spend, and billing cycle. Redirects are refused, and the request has no cookie store and no cache. After a `429`, nothing is read or sent until cursor.com's `Retry-After` passes.

rusage never stores, logs, or displays the token, and it never reads browser cookies or Cursor projects. Turning off `Settings › Tools › Cursor` turns usage off and stops all reads.

## Token Usage

When Token Usage is on and a tool is connected, the Token Usage card adds that tool's daily tokens:

- Claude Code: rusage reads Claude Code's session transcripts under `~/.claude/projects` (or `CLAUDE_CONFIG_DIR`) on this Mac. From each assistant row it keeps only the response IDs, timestamp, model name, and token counts. It never keeps prompts, responses, tool output, or file paths from the transcripts. The derived rows are cached in `~/Library/Caches/rusage/claude-token-usage-cache.json`, keyed by the transcript's path relative to the projects folder, so history survives Claude Code's 30-day transcript cleanup. Nothing leaves the Mac.
- Cursor: rusage sends Cursor's sign-in token to cursor.com's dashboard usage-events endpoint, the one Cursor's own usage page uses, and keeps only each event's timestamp, model, and token counts in memory. This endpoint is not a documented public API and may change.

## What rusage Does Not Require By Default

Normal rusage usage does not require:

- browser cookies;
- hidden browser windows or hidden WebViews;
- ChatGPT web dashboard scraping;
- Full Disk Access;
- Screen Recording;
- Accessibility permissions.

Accessibility may still be useful for development or validation tooling that inspects native UI, but it is not a product requirement for normal account switching or limit monitoring.

## Network And External Services

rusage talks to Codex through local Codex surfaces. When Claude Code usage is on, it also calls api.anthropic.com with Claude Code's own sign-in token. When you use rusage's own Claude sign-in, it calls platform.claude.com to sign in, renew and revoke, and api.anthropic.com with that sign-in's token. When Cursor usage is on, it calls cursor.com with Cursor's own sign-in token. It must not send Codex auth snapshots, raw auth payloads, or tokens to analytics services, crash-reporting systems, issue trackers, or any other third-party API. A token may go only to the service that issued it.

If future features add status-page checks, diagnostics export, or usage statistics, they must keep the same rule: aggregate or redact data before it leaves the machine, and never include raw auth payloads or tokens.

## Logging And Diagnostics

Logs and diagnostics may include high-level workflow events, rate-limit percentages, and error categories. Account identifiers, host names, and local paths should be treated as private by default in support artifacts. Logs and diagnostics must not include raw auth snapshots, token values, API keys, or complete auth payloads.

When a Claude Code or Cursor usage read fails, rusage writes one line to the macOS log with the tool and the error category only: network, an HTTP status code, unauthorized, rate limited, parse, or Keychain access. It never logs a token, an email, an account ID, or a URL.

rusage's own Claude sign-in logs only what happened: a renewal attempt, its outcome (ok, invalid grant, network, rejected, malformed, save failed, busy), an unfinished renewal found at launch, and whether a sign-in was saved or removed. It never logs a token, an email, a code, a URL with a query, or a response body.

When sharing logs for debugging, review them first and redact account identifiers, host names, or paths when needed.

rusage's user-initiated diagnostic report export is a redacted JSON support artifact. It uses per-export aliases for accounts, summarizes freshness and result categories, and includes a manifest of omitted, summarized, and rejected field classes. The export must be built from allowlisted fields and must not include raw logs, raw auth JSON, saved snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, refresh tokens, stable account IDs, prompt/session content, or raw stderr.
