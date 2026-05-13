# Refresh Accounts

## Isolated Saved-Account Status Reads

Status: `accepted for inactive local catalog refresh`

Date: 2026-04-30

### Decision

Refresh Accounts may refresh inactive saved local catalog accounts through isolated Codex app-server reads.

For each inactive saved account, CodexPill creates a temporary isolated `CODEX_HOME`, writes that account's saved snapshot as `auth.json`, runs `codex app-server`, and reads status without switching or restoring the user's live local Codex auth. The app-server session must stay open until the `account/rateLimits/read` response arrives or the read times out.

Meaningful previous rate-limit data remains authoritative when the isolated read fails or returns partial, missing, zeroed, or otherwise suspicious rate-limit data. CodexPill must not introduce background live-auth switch-and-restore for this refresh path.

### Evidence

Sanitized manual probe:

- Codex executable: `/Applications/Codex.app/Contents/Resources/codex`
- Codex version: `codex-cli 0.126.0-alpha.8`
- Isolated environment: temporary `CODEX_HOME` directory named with the `CodexPill-CODEX_HOME-spike-<random>` prefix, seeded only with a saved snapshot copied to `auth.json`, with a `tmp` subdirectory and `TMPDIR` scoped to that isolated root.
- Saved catalog shape observed: 10 saved accounts and 10 saved snapshots.
- Status source: `codex app-server` over stdio with `initialize`, `initialized`, `account/read`, and `account/rateLimits/read` requests.
- Account identity read: yes.
- Plan read: yes.
- Session limit read: yes.
- Weekly limit read: yes.
- Complete limit source: `result.rateLimitsByLimitId["codex"]` when present and complete, with `result.rateLimits` as the legacy fallback.
- Live local auth changed: no. The live `~/.codex/auth.json` hash, size, and modification time were unchanged before and after the isolated probe.
- App-server process behavior: a child `codex app-server` process was launched by the probe and exited without probe termination. Existing app-server process count was unchanged before and after the probe.
- Temporary state cleanup: the isolated root was removed after the probe.
- Secret handling: no auth payloads, tokens, device codes, raw snapshots, account identifiers, or email addresses were printed or committed.

Control probe:

- The original probe produced `complete_response_ids: [1, 2]` and never received the `account/rateLimits/read` response id before the process exited after about 1.18 seconds.
- The corrected probe kept stdin/session alive after sending `account/rateLimits/read`, then waited for the rate-limit response id or timeout.
- Across the visible saved account catalog, isolated `CODEX_HOME` reads returned account metadata plus complete session and weekly windows.

### Refresh Semantics

For inactive saved catalog accounts:

- read each saved snapshot from the local catalog and seed a temporary isolated `CODEX_HOME/auth.json`;
- send `initialize`, `initialized`, `account/read`, and `account/rateLimits/read`;
- keep stdin/session open until rate limits arrive or a timeout fires;
- prefer complete `result.rateLimitsByLimitId["codex"]` values over `result.rateLimits`;
- preserve previous meaningful rate-limit windows on failed, missing, partial, zeroed, or suspicious isolated reads;
- never mutate the live local `~/.codex/auth.json`;
- keep remote inactive-account refresh behavior separate unless it is proven through the same isolated-read path.

The safest status source remains `codex app-server` launched as a short-lived child process with isolated `CODEX_HOME`, because it works for account identity, plan, and complete rate-limit windows without mutating live auth.

### Follow-Up Trigger

Revisit this path if Codex changes the app-server protocol shape or if remote inactive-account refresh should use isolated saved-account reads too.

## Active Local Snapshot Relinking

Status: `accepted for active local refresh`

Date: 2026-05-06

### Decision

When refreshing the active local account, CodexPill may relink that saved account's snapshot from the current live local auth if the resolved Codex account identity is the same but the auth fingerprint changed.

This handles the case where the user signs back into Codex outside CodexPill. The saved catalog entry still represents the same account, but the saved auth snapshot can contain a revoked refresh token. Relinking the active saved snapshot prevents later remote install/switch flows from copying stale auth to a host.

### Refresh Semantics

For the active local account:

- read current account identity and rate-limit status from the local Codex app-server;
- resolve the returned identity to exactly one saved account;
- if current live auth has a different fingerprint for that same saved account, overwrite that saved account's snapshot with current live auth;
- preserve the saved account id, display name, and catalog position;
- then apply returned email, plan, and rate-limit metadata as normal.

For inactive saved accounts, CodexPill must keep using isolated saved-account status reads and must not rotate inactive snapshots through the real local auth file.
