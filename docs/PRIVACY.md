# Privacy And Data Handling

CodexPill is a local macOS menubar utility for Codex account switching, limit visibility, and remote-host account setup. Its most sensitive data is Codex authentication state. Treat saved account snapshots as secrets.

## What CodexPill Reads

During normal use, CodexPill may read:

- `~/.codex/auth.json` to identify and save the currently active Codex account.
- Codex account metadata exposed by Codex, such as email address, plan type, account identity, and rate-limit windows.
- Local Codex app-server status to refresh account and limit information.
- Local process information to detect running Codex CLI sessions when a switch may require a restart or user action.
- CodexPill-owned state under `~/Library/Application Support/CodexPill`.

When a remote host is configured, CodexPill may also read:

- Remote Codex app-server status over SSH.
- The remote host's `.codex/auth.json` only to verify which Codex account is active on that host.
- CodexPill-owned remote snapshot state under `.codexpill/snapshots`.

## What CodexPill Writes Or Stores

CodexPill writes and stores:

- A local account catalog under `~/Library/Application Support/CodexPill`.
- Saved Codex auth snapshots under `~/Library/Application Support/CodexPill/snapshots`.
- `~/.codex/auth.json` when switching the active local Codex account.
- Temporary isolated `CODEX_HOME` state when capturing a new Codex sign-in without mutating the current account.

Saved auth snapshots contain authentication material and must be handled like credentials. They should not be printed, logged, attached to issues, or committed to git.

## Remote Hosts

If you configure a remote host, CodexPill can copy a selected saved auth snapshot to that host over SSH. The current remote storage contract is:

- copied snapshots live under `.codexpill/snapshots` on the remote host;
- switching on the remote host copies the selected snapshot into `.codex/auth.json`;
- CodexPill may restart or refresh the remote Codex app-server so the host uses the selected account.

CodexPill must not upload auth snapshots or tokens anywhere except explicit user-configured remote hosts selected by the user.

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

CodexPill talks to Codex through local Codex surfaces and user-configured SSH destinations. It should not send auth snapshots, raw auth payloads, or tokens to analytics services, crash-reporting systems, issue trackers, or third-party APIs.

If future features add status-page checks, diagnostics export, or usage statistics, they must keep the same rule: aggregate or redact data before it leaves the machine, and never include raw auth payloads or tokens.

## Logging And Diagnostics

Logs and diagnostics may include high-level workflow events, rate-limit percentages, and error categories. Account identifiers, host names, local paths, and remote destinations should be treated as private by default in support artifacts. Logs and diagnostics must not include raw auth snapshots, token values, API keys, or complete auth payloads.

When sharing logs for debugging, review them first and redact account identifiers, host names, or paths when needed.

CodexPill's user-initiated diagnostic report export is a redacted JSON support artifact. It uses per-export aliases for accounts and hosts, summarizes freshness and result categories, and includes a manifest of omitted, summarized, and rejected field classes. The export must be built from allowlisted fields and must not include raw logs, raw auth JSON, saved snapshots, raw UserDefaults, raw SSH output, emails, hostnames, local paths, tokens, refresh tokens, stable account IDs, prompt/session content, or raw stderr.
