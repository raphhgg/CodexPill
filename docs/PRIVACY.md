# Privacy And Data Handling

Refill is a local macOS menubar utility for Codex account switching and limit visibility. It can also show Claude Code and Cursor usage if you connect them. For those two tools it only reads. It never writes their files or Keychain items. The one thing it runs is `claude doctor`, which lets Claude Code renew its own expired sign-in. Its most sensitive data is Codex authentication state. Treat saved account snapshots as secrets.

Refill was called CodexPill before. On its first launch Refill copies CodexPill's saved Codex accounts and settings into its own folder and preferences, unless Refill already has data. It does not copy Claude or Cursor accounts a test build may have saved. It never changes or deletes CodexPill's copies. [Uninstall And Reset](UNINSTALL_RESET.md) explains how to remove them.

## What Refill Reads

During normal use, Refill may read:

- `~/.codex/auth.json` to identify and save the currently active Codex account.
- Codex account metadata exposed by Codex, such as email address, plan type, account identity, rate-limit windows, and limit reset credits.
- Local Codex app-server status to refresh account and limit information.
- Local process information to detect running Codex CLI sessions when a switch may require a restart or user action.
- Refill-owned state under `~/Library/Application Support/Refill`.
- Claude Code's sign-in, from `~/.claude/.credentials.json` or the `Claude Code-credentials` Keychain item, while Claude Code usage is connected. See [Claude Code](#claude-code).
- Local process information to detect a running terminal Claude Code before letting Claude Code renew its expired sign-in.
- Cursor's access token and cached email from Cursor's local database, while Cursor usage is connected. See [Cursor](#cursor).

## What Refill Writes Or Stores

Refill writes and stores:

- A local account catalog under `~/Library/Application Support/Refill`.
- Saved Codex auth snapshots under `~/Library/Application Support/Refill/snapshots`.
- `~/.codex/auth.json` when switching the active local Codex account.
- Temporary isolated `CODEX_HOME` state when capturing a new Codex sign-in without mutating the current account.

Saved auth snapshots contain authentication material and must be handled like credentials. They should not be printed, logged, attached to issues, or committed to git.

## Codex Auth Stays On This Mac

Refill never copies Codex auth snapshots or Codex tokens to another machine or service. Earlier versions could copy a selected snapshot to an SSH host you configured. That feature is gone. [Uninstall And Reset](UNINSTALL_RESET.md) explains how to remove what it left on a host.

## Claude Code

Refill never signs in to Claude, never calls Anthropic's token endpoint, and never reads, sends, or renews Claude Code's refresh token. It only uses the sign-in Claude Code already has, and it never writes Claude Code's files or Keychain item.

**Usage (optional, off by default).** Checking `Appearance › Show Tools › Claude` asks for consent before anything is read. While it is connected, each read:

- reads `.credentials.json` in Claude Code's config folder (`CLAUDE_CONFIG_DIR`, or `~/.claude`), and if that file holds no Claude sign-in, the login Keychain generic password with service `Claude Code-credentials` and your macOS user name as the account. Refill reads that item by running `/usr/bin/security find-generic-password -w`, the same command Claude Code uses. Claude Code creates the item with `security`, so `security` can read it without a prompt. The password comes back through a pipe and is never logged;
- uses only the access token, its expiry, and the plan name from that sign-in;
- reads the plan tier and your email from `oauthAccount` in Claude Code's global config (`$CLAUDE_CONFIG_DIR/.claude.json`, or `~/.claude.json`). The email shows in the Claude side menu, masked with Hide Emails;
- sends the access token to one place, `GET https://api.anthropic.com/api/oauth/usage`, to fetch your 5-hour and weekly limits. Redirects to any other host, or to plain HTTP, are refused. The request has no cookies and no cache.

If macOS refuses `security` access, for example while the Keychain is locked, the card keeps the last limits and offers `Allow Keychain Access…`. That retry gives you time to answer a macOS prompt. Refill never stores, logs, or displays the token, and it never reads browser cookies or Claude conversations. Unchecking `Appearance › Show Tools › Claude` turns usage off and stops all reads.

**Renewal by Claude Code.** When Claude Code usage is connected, Claude Code's live token has expired, and no terminal `claude` session runs, Refill runs `claude doctor` with Claude Code's own config folder (no `CLAUDE_CONFIG_DIR` unless Claude Code itself uses one). Claude Code renews its own sign-in, makes no model call, and saves the result where it always does. Refill only reads the new expiry, then reads usage again. It runs at most once per expiry, and again for the same expiry only after 30 minutes.

Refill runs the `claude` command it finds in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, or `/usr/local/bin`, with only `HOME`, `USER`, `LOGNAME`, `PATH`, `TMPDIR`, and `CLAUDE_CONFIG_DIR` set, so none of your shell variables, such as an API key, reach it. Its output is discarded. The process check counts only terminal `claude` sessions. The Claude desktop app's own Claude Code, under `~/Library/Application Support/Claude/claude-code/`, is ignored because it keeps its own sign-in. If the process table can't be read, Refill treats Claude Code as running.

## Cursor

Refill never signs in to Cursor, never asks Cursor for a new token, and never sends Cursor's refresh token anywhere. It only uses the sign-in Cursor already has. Cursor keeps it in a SQLite database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, and Refill reads it only by key, never by scanning.

**Usage (optional, off by default).** Checking `Appearance › Show Tools › Cursor` asks for consent before anything is read. While it is connected, each read:

- opens that database read-only and reads two rows, `cursorAuth/accessToken` and `cursorAuth/cachedEmail`. The email shows in the Cursor side menu, masked with Hide Emails. When Cursor is closed, the database is opened so that no file is created next to it; when Cursor has it open, SQLite reads only committed data;
- uses the token only while it is more than a minute from expiry;
- sends the token to one place, `GET https://cursor.com/api/usage-summary`, as Cursor's session cookie, to fetch your plan usage, on-demand spend, and billing cycle. Redirects are refused, and the request has no cookie store and no cache. After a `429`, nothing is read or sent until cursor.com's `Retry-After` passes.

Refill never stores, logs, or displays the token, and it never reads browser cookies or Cursor projects. Unchecking `Appearance › Show Tools › Cursor` turns usage off and stops all reads.

## What Refill Does Not Require By Default

Normal Refill usage does not require:

- browser cookies;
- hidden browser windows or hidden WebViews;
- ChatGPT web dashboard scraping;
- Full Disk Access;
- Screen Recording;
- Accessibility permissions.

Accessibility may still be useful for development or validation tooling that inspects native UI, but it is not a product requirement for normal account switching or limit monitoring.

## Network And External Services

Refill talks to Codex through local Codex surfaces. When Claude Code usage is on, it also calls api.anthropic.com with Claude Code's own sign-in token, and `claude doctor` lets Claude Code talk to Anthropic itself to renew an expired sign-in. When Cursor usage is on, it calls cursor.com with Cursor's own sign-in token. It must not send Codex auth snapshots, raw auth payloads, or tokens to analytics services, crash-reporting systems, issue trackers, or any other third-party API. A token may go only to the service that issued it.

If future features add status-page checks, diagnostics export, or usage statistics, they must keep the same rule: aggregate or redact data before it leaves the machine, and never include raw auth payloads or tokens.

## Logging And Diagnostics

Logs and diagnostics may include high-level workflow events, rate-limit percentages, and error categories. Account identifiers, host names, and local paths should be treated as private by default in support artifacts. Logs and diagnostics must not include raw auth snapshots, token values, API keys, or complete auth payloads.

When a Claude Code or Cursor usage read fails, Refill writes one line to the macOS log with the tool and the error category only: network, an HTTP status code, unauthorized, rate limited, parse, or Keychain access. It never logs a token, an email, an account ID, or a URL.

When sharing logs for debugging, review them first and redact account identifiers, host names, or paths when needed.

Refill's user-initiated diagnostic report export is a redacted JSON support artifact. It uses per-export aliases for accounts, summarizes freshness and result categories, and includes a manifest of omitted, summarized, and rejected field classes. The export must be built from allowlisted fields and must not include raw logs, raw auth JSON, saved snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, refresh tokens, stable account IDs, prompt/session content, or raw stderr.
