# Privacy And Data Handling

CodexPill is a local macOS menubar utility for Codex account switching and limit visibility. It can also show Claude Code and Cursor usage if you connect them, and switch Claude Code or Cursor between sign-ins you saved. Its most sensitive data is Codex authentication state. Treat saved account snapshots as secrets.

## What CodexPill Reads

During normal use, CodexPill may read:

- `~/.codex/auth.json` to identify and save the currently active Codex account.
- Codex account metadata exposed by Codex, such as email address, plan type, account identity, rate-limit windows, and limit reset credits.
- Local Codex app-server status to refresh account and limit information.
- Local process information to detect running Codex CLI sessions when a switch may require a restart or user action.
- CodexPill-owned state under `~/Library/Application Support/CodexPill`.
- Claude Code's sign-in, from `~/.claude/.credentials.json` or the `Claude Code-credentials` Keychain item, while Claude Code usage is connected or when you save or switch a Claude Code account. See [Claude Code](#claude-code).
- Local process information to detect a running terminal Claude Code before switching Claude Code accounts or renewing the live sign-in.
- Cursor's access token from Cursor's local database, while Cursor usage is connected, and Cursor's sign-in rows from the same database when you save or switch a Cursor account. See [Cursor](#cursor).
- The sign-in rows of a temporary Cursor profile while you add a Cursor account. See [Cursor](#cursor).

## What CodexPill Writes Or Stores

CodexPill writes and stores:

- A local account catalog under `~/Library/Application Support/CodexPill`.
- Saved Codex auth snapshots under `~/Library/Application Support/CodexPill/snapshots`.
- `~/.codex/auth.json` when switching the active local Codex account.
- Temporary isolated `CODEX_HOME` state when capturing a new Codex sign-in without mutating the current account.
- Saved Claude Code accounts in `CodexPill Claude Code account` Keychain items and `claude-code-accounts.json`, and Claude Code's own sign-in when you switch Claude Code accounts. See [Claude Code](#claude-code).
- Temporary Claude Code config folders under `~/Library/Application Support/CodexPill/claude-sign-in`, each with a `Claude Code-credentials-<hash>` Keychain item Claude Code creates, while you add a Claude account or while Claude Code renews a saved one. CodexPill deletes both when the run ends. See [Claude Code](#claude-code).
- Saved Cursor accounts in one `CodexPill Cursor accounts` Keychain item, and Cursor's sign-in rows in its local database when you switch Cursor accounts. See [Cursor](#cursor).
- Temporary Cursor profiles under `~/Library/Application Support/CodexPill/cursor-sign-in` while you add a Cursor account. CodexPill deletes each one when the sign-in ends. See [Cursor](#cursor).

Saved auth snapshots contain authentication material and must be handled like credentials. They should not be printed, logged, attached to issues, or committed to git.

## Codex Auth Stays On This Mac

CodexPill never copies Codex auth snapshots or Codex tokens to another machine or service. Earlier versions could copy a selected snapshot to an SSH host you configured. That feature is gone. [Uninstall And Reset](UNINSTALL_RESET.md) explains how to remove what it left on a host.

## Claude Code

CodexPill never signs in to Claude with its own code, never calls Anthropic's token endpoint, and never reads, sends, or renews a refresh token itself. Signing in and renewing are done by Claude Code, through the commands listed below. CodexPill may run `claude doctor` so Claude Code renews its own sign-in, but only when that sign-in has expired and no terminal `claude` session runs. The Claude desktop app's own Claude Code is ignored because it keeps its own sign-in.

**Usage (optional, off by default).** `Settings › Add Account › Claude…` asks for consent before anything is read. While it is connected, each read:

- reads `.credentials.json` in Claude Code's config folder (`CLAUDE_CONFIG_DIR`, or `~/.claude`), and if that file holds no Claude sign-in, the login Keychain generic password with service `Claude Code-credentials` and your macOS user name as the account;
- uses only the access token, its expiry, and the plan name from that sign-in;
- sends the access token to one place, `GET https://api.anthropic.com/api/oauth/usage`, to fetch your 5-hour and weekly limits. Redirects to any other host, or to plain HTTP, are refused. The request has no cookies and no cache.

macOS may ask you to allow Keychain access. CodexPill shows that prompt only right after you connect or choose `Allow Keychain access…`. CodexPill never logs or displays the token, and it never reads browser cookies or Claude conversations. `Disconnect Claude` turns usage off and stops all reads.

**What CodexPill stores for each saved Claude account.** Each saved account is that account's Claude Code sign-in:

- a copy of the `claudeAiOauth` object (access token, refresh token, expiry, scopes, plan) and the `oauthAccount` object (account and organization IDs, email) in a login Keychain item CodexPill owns, service `CodexPill Claude Code account`, one item per saved account, with the account's CodexPill ID as the Keychain account. These tokens can use your Claude plan, so treat the items as secrets;
- the account's name, email, organization name, plan, Claude account IDs, and last 5-hour and weekly limits, but no tokens, in `~/Library/Application Support/CodexPill/claude-code-accounts.json`.

**Commands CodexPill runs.** CodexPill runs the `claude` command it finds in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, or `/usr/local/bin`, with only `HOME`, `USER`, `LOGNAME`, `PATH`, `TMPDIR`, and `CLAUDE_CONFIG_DIR` set, so none of your shell variables, such as an API key, reach it. Its output is discarded.

- `claude auth login --claudeai` when you choose `Add Claude Account…` or `Sign In…`. Claude Code opens Claude's sign-in page in your browser. It runs in a new folder, `~/Library/Application Support/CodexPill/claude-sign-in/<random id>`, set as `CLAUDE_CONFIG_DIR`, so your current Claude Code sign-in is not touched. When Claude Code has no sign-in at all, it runs without `CLAUDE_CONFIG_DIR`, so Claude Code itself is signed in.
- `claude doctor` in a new folder of the same kind, when a saved account that is not in use has an expired token. CodexPill first writes that account's saved sign-in into the folder as `.credentials.json` and `.claude.json` (readable only by you). Claude Code renews the token, makes no model call, and saves the result in the folder's Keychain item. CodexPill copies it into the account's `CodexPill Claude Code account` item, only if that item did not change meanwhile.
- `claude doctor` with Claude Code's own config folder (no `CLAUDE_CONFIG_DIR` unless Claude Code itself uses one), when Claude Code usage is connected, Claude Code's live token has expired, and no `claude` process runs. Claude Code renews its own sign-in and saves it where it always does; CodexPill only reads the new expiry, then reads usage again. It runs at most once per expiry, and again for the same expiry only after 30 minutes.
- `/usr/bin/security find-generic-password` and `delete-generic-password` for the folder's `Claude Code-credentials-<first 8 hex of sha256(folder path)>` item, to read it and then delete it.

When a run ends, whether it succeeded, failed, timed out, or you cancelled it, CodexPill deletes the folder and its Keychain item. A folder left behind by a crash is deleted with its item the next time CodexPill launches.

**Inactive accounts' limits.** Every 15 minutes, for each saved account Claude Code is not signed in to, CodexPill sends that account's own access token to the usage address above. It never sends one account's token on behalf of another.

**Saving the current sign-in and switching.** `Save Current Sign-In` reads Claude Code's sign-in as above, and `oauthAccount` from Claude Code's global config (`$CLAUDE_CONFIG_DIR/.claude.json`, or `~/.claude.json`), and saves them as described. Switching also writes Claude Code's own sign-in:

- it updates the existing `Claude Code-credentials` Keychain item, or `.credentials.json` when the sign-in lives there. Only `claudeAiOauth` changes; other keys, such as MCP sign-ins, stay as they were. CodexPill never creates or deletes Claude Code's Keychain item;
- it replaces `oauthAccount` in Claude Code's global config and keeps every other key;
- it reads the process table first and refuses to switch while a terminal `claude` session runs. The Claude desktop app's own Claude Code, under `~/Library/Application Support/Claude/claude-code/`, is ignored because it keeps its own sign-in. If the process table can't be read, CodexPill treats Claude Code as running.

If any step fails, CodexPill puts back every file and item it had already changed.

## Cursor

CodexPill never signs in to Cursor with its own code, never asks Cursor for a new token, and never sends Cursor's refresh token anywhere. A new account is signed in by Cursor itself, in a separate Cursor window. Cursor keeps its sign-in in a SQLite database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, and CodexPill reads it only by key, never by scanning.

**Usage (optional, off by default).** `Settings › Add Account › Cursor…` asks for consent before anything is read. While it is connected, each read:

- opens that database read-only and reads one row, `cursorAuth/accessToken`. When Cursor is closed, the database is opened so that no file is created next to it; when Cursor has it open, SQLite reads only committed data;
- uses the token only while it is more than a minute from expiry;
- sends the token to one place, `GET https://cursor.com/api/usage-summary`, as Cursor's session cookie, to fetch your plan usage, on-demand spend, and billing cycle. Redirects are refused, and the request has no cookie store and no cache. After a `429`, nothing is read or sent until cursor.com's `Retry-After` passes.

CodexPill never stores, logs, or displays the token, and it never reads browser cookies or Cursor projects. `Disconnect Cursor` turns usage off and stops all reads.

**Saved Cursor accounts.** CodexPill can save Cursor sign-ins and switch between them. Only a user action adds, switches or removes one, and switching makes no network call. Saving one copies the eight `cursorAuth/*` rows that are a Cursor sign-in (`accessToken`, `refreshToken`, `cachedEmail`, `cachedScopedProfile`, `cachedSignUpType`, `stripeMembershipAuthId`, `stripeMembershipType`, `stripeSubscriptionStatus`) into one login Keychain item CodexPill owns, service `CodexPill Cursor accounts`, with the name you give it. Those rows include Cursor's tokens and your Cursor email. The same item keeps each account's last limits (plan, percent used, on-demand spend, billing cycle, and when they were read). Nothing about them goes to a file.

**Adding a Cursor account.** `Add Cursor Account…` opens a second Cursor window next to yours:

- it starts a new Cursor instance with `--user-data-dir` and `--extensions-dir` set to a new folder, `~/Library/Application Support/CodexPill/cursor-sign-in/<8 random characters>`, readable only by you. Your own Cursor profile is not opened, read, or changed, and your own Cursor keeps running;
- you sign in there. CodexPill reads the folder's `state.vscdb` once a second, by key, until the `cursorAuth/*` rows appear, then quits that window by its process ID. It never quits any other Cursor. If the window does not quit within 10 seconds, it is force-quit;
- it saves those rows as described above, then deletes the folder.

When the sign-in ends, whether it succeeded, failed, timed out after 5 minutes, or you cancelled it, the window is quit and the folder deleted. A folder left behind by a crash is deleted the next time CodexPill launches.

The temporary window is a full Cursor, so while it runs it also uses your user-wide Cursor folder, `~/.cursor`. It starts the MCP servers listed in `~/.cursor/mcp.json`, and it writes to `~/.cursor/ai-tracking`, as any Cursor window does. CodexPill itself does not read or change those files.

**Inactive accounts' limits.** Every 15 minutes, for each saved account Cursor is not signed in to, CodexPill sends that account's own access token to the usage address above. It never sends one account's token on behalf of another. CodexPill never renews a saved token: Cursor renews a token only while it runs with that account. Once a saved token is within a minute of expiry, nothing is sent for that account, and the menu shows its last limits with the time they were read. Switching to it hands it to Cursor, which renews it.

Switching quits and changes Cursor:

- it asks Cursor to quit and waits for it to exit. It never force-quits, so Cursor can ask about unsaved work. If Cursor is still running, nothing is written;
- it refuses to write while any other process still holds the database;
- it saves the outgoing sign-in again, because Cursor may have renewed its tokens, then writes the chosen account's eight rows into `state.vscdb` in one transaction. No other row and no other Cursor file changes;
- it opens Cursor again. If a step fails after Cursor quit, the database is left as it was and Cursor reopens on the sign-in it had.

While a Cursor account is being added, switching Cursor is refused, because a switch quits every Cursor, including the sign-in window.

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

CodexPill talks to Codex through local Codex surfaces. When Claude Code usage is on, it also calls api.anthropic.com with Claude Code's own sign-in token, and with each saved Claude account's own token for that account's limits. Adding a Claude account and renewing a saved one run Claude Code, which talks to Anthropic itself. When Cursor usage is on, it calls cursor.com with Cursor's own sign-in token, and with each saved Cursor account's own token for that account's limits. Adding a Cursor account runs Cursor, which talks to Cursor's servers itself. Switching Claude Code or Cursor accounts makes no network call. It must not send Codex auth snapshots, raw auth payloads, or tokens to analytics services, crash-reporting systems, issue trackers, or any other third-party API. A token may go only to the service that issued it.

If future features add status-page checks, diagnostics export, or usage statistics, they must keep the same rule: aggregate or redact data before it leaves the machine, and never include raw auth payloads or tokens.

## Logging And Diagnostics

Logs and diagnostics may include high-level workflow events, rate-limit percentages, and error categories. Account identifiers, host names, and local paths should be treated as private by default in support artifacts. Logs and diagnostics must not include raw auth snapshots, token values, API keys, or complete auth payloads.

When sharing logs for debugging, review them first and redact account identifiers, host names, or paths when needed.

CodexPill's user-initiated diagnostic report export is a redacted JSON support artifact. It uses per-export aliases for accounts, summarizes freshness and result categories, and includes a manifest of omitted, summarized, and rejected field classes. The export must be built from allowlisted fields and must not include raw logs, raw auth JSON, saved snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, refresh tokens, stable account IDs, prompt/session content, or raw stderr.
