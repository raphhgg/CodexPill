# Privacy And Data Handling

CodexPill is a local macOS menubar utility for Codex account switching and limit visibility. It can also show Claude Code and Cursor usage if you connect them. Its most sensitive data is Codex authentication state. Treat saved account snapshots as secrets.

## What CodexPill Reads

During normal use, CodexPill may read:

- `~/.codex/auth.json` to identify and save the currently active Codex account.
- Codex account metadata exposed by Codex, such as email address, plan type, account identity, and rate-limit windows.
- Local Codex app-server status to refresh account and limit information.
- Local process information to detect running Codex CLI sessions when a switch may require a restart or user action.
- CodexPill-owned state under `~/Library/Application Support/CodexPill`.
- CodexPill's own Claude sign-in, in the `CodexPill Claude sign-in` Keychain item, only while Claude usage is connected.
- Claude Code's sign-in, from `~/.claude/.credentials.json` or the `Claude Code-credentials` Keychain item, read-only and only as a fallback while Claude usage is connected.
- Cursor's sign-in token from Cursor's local database, only while Cursor usage is turned on.

## What CodexPill Writes Or Stores

CodexPill writes and stores:

- A local account catalog under `~/Library/Application Support/CodexPill`.
- Saved Codex auth snapshots under `~/Library/Application Support/CodexPill/snapshots`.
- `~/.codex/auth.json` when switching the active local Codex account.
- Temporary isolated `CODEX_HOME` state when capturing a new Codex sign-in without mutating the current account.

Saved auth snapshots contain authentication material and must be handled like credentials. They should not be printed, logged, attached to issues, or committed to git.

## Claude And Cursor Usage

These features are display-only. CodexPill does not switch or manage Claude or Cursor accounts. It signs in to Claude only to read usage, and never signs in to Cursor.

**Claude usage (optional).** Claude usage is off by default. `Connect Claude…` asks for consent first. Confirming opens your browser on Claude's own sign-in page (`claude.com`), using the same public OAuth client as Claude Code with PKCE and a one-time listener on `localhost` for the answer. CodexPill asks only for the `user:profile` scope. It stores the resulting access token, refresh token, and expiry in one item in your login Keychain (`CodexPill Claude sign-in`), never in a file. It sends them only to Anthropic: the tokens to `platform.claude.com` to refresh or revoke the sign-in, and the access token to `api.anthropic.com` to fetch your 5-hour and weekly limits. Requests that carry a token refuse redirects to other hosts. If you have no CodexPill sign-in, CodexPill falls back to Claude Code's sign-in, read-only, from `~/.claude/.credentials.json` (or `CLAUDE_CONFIG_DIR`) or the `Claude Code-credentials` Keychain item, and only while that token is unexpired. It never changes, refreshes, or stores Claude Code's sign-in. macOS may ask you to allow Keychain access, and CodexPill shows that prompt only right after you sign in or choose `Allow Keychain access…`. CodexPill never logs or displays a token, and never reads browser cookies or Claude conversation data. `Disconnect Claude…` deletes CodexPill's Keychain item, asks Anthropic to revoke that sign-in, and stops all reads.

**Cursor usage (optional).** Cursor usage is off by default. `Connect Cursor…` asks for consent before anything is read. While it is on, CodexPill reads Cursor's sign-in token from `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`. It opens that database read-only, reads only the token, and never changes Cursor's files. CodexPill sends the token only to cursor.com, to fetch your plan usage, on-demand spend, and billing cycle. It refuses redirects, so the token never goes to another host. It never stores, logs, displays, or refreshes the token, and it never reads browser cookies. `Disconnect Cursor…` turns the feature off and stops all reads.

## Codex Auth Stays On This Mac

CodexPill never copies Codex auth snapshots or Codex tokens to another machine or service. Earlier versions could copy a selected snapshot to an SSH host you configured. That feature is gone. [Uninstall And Reset](UNINSTALL_RESET.md) explains how to remove what it left on a host.

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

CodexPill talks to Codex through local Codex surfaces. When Claude usage is on, it also calls Anthropic (`platform.claude.com` for CodexPill's own sign-in, `api.anthropic.com` for usage) with CodexPill's own Claude sign-in, or with Claude Code's sign-in as a fallback. When Cursor usage is on, it calls cursor.com with Cursor's own sign-in token. It must not send Codex auth snapshots, raw auth payloads, or tokens to analytics services, crash-reporting systems, issue trackers, or any other third-party API. A token may go only to the service that issued it.

If future features add status-page checks, diagnostics export, or usage statistics, they must keep the same rule: aggregate or redact data before it leaves the machine, and never include raw auth payloads or tokens.

## Logging And Diagnostics

Logs and diagnostics may include high-level workflow events, rate-limit percentages, and error categories. Account identifiers, host names, and local paths should be treated as private by default in support artifacts. Logs and diagnostics must not include raw auth snapshots, token values, API keys, or complete auth payloads.

When sharing logs for debugging, review them first and redact account identifiers, host names, or paths when needed.

CodexPill's user-initiated diagnostic report export is a redacted JSON support artifact. It uses per-export aliases for accounts, summarizes freshness and result categories, and includes a manifest of omitted, summarized, and rejected field classes. The export must be built from allowlisted fields and must not include raw logs, raw auth JSON, saved snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, refresh tokens, stable account IDs, prompt/session content, or raw stderr.
