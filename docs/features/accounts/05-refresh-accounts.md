# Refresh Accounts

## Isolated Saved-Account Status Reads

Status: `accepted for inactive local catalog refresh`

Date: 2026-04-30

### Decision

Refresh Accounts may refresh inactive saved local catalog accounts through isolated Codex app-server reads.

For each inactive saved account, CodexPill creates a temporary isolated `CODEX_HOME`, writes that account's saved snapshot as `auth.json`, runs `codex app-server`, and reads status without switching or restoring the user's live local Codex auth. The app-server session must stay open until the `account/rateLimits/read` response arrives or the read times out.

Meaningful previous rate-limit data remains authoritative when the isolated read fails or returns partial, missing, zeroed, or otherwise suspicious rate-limit data. CodexPill must not introduce background live-auth switch-and-restore for this refresh path.

Inactive reads send `account/read` with `refreshToken: false`. Codex can still rotate tokens during the read when the access token is near expiry. Refresh tokens are single-use, so CodexPill reads the isolated `auth.json` back before cleanup. If it changed, CodexPill writes it to that account's saved snapshot only when its identity resolves exactly, by stable or scoped account id, to the same saved account, and only when the saved snapshot still matches the one the read started from. Otherwise it discards the rotated auth. The write-back also runs when the status read fails.

Inactive refresh runs on the scheduled refresh tick after the active refresh, at most once every 15 minutes. Accounts are read one at a time. The refresh does not start while another account operation is busy.

Switch, remove, and add wait for the account being read to finish, then the refresh stops. A rotated token is saved before the operation touches auth. Each result merges into the current account list by account id. It never replaces the list or the active account, so a removed account stays removed.

Before switching away from the active account, CodexPill saves the live `~/.codex/auth.json` to that account's snapshot if Codex rotated it since it was saved.

### Evidence

Sanitized manual probe:

- Codex executable: `/Applications/Codex.app/Contents/Resources/codex`
- Codex version: `codex-cli 0.126.0-alpha.8`
- Isolated environment: temporary `CODEX_HOME` directory named with a `CodexPill-CODEX_HOME-<random>` prefix, seeded only with a saved snapshot copied to `auth.json`, with a `tmp` subdirectory and `TMPDIR` scoped to that isolated root.
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

Token rotation, from codex-rs at `rust-v0.161.0` (`login/src/auth/manager.rs`, app-server `account_processor.rs`):

- `account/read` with `refreshToken: true` calls `refresh_token()` on every read, so every read rotates the refresh token.
- With `refreshToken: false`, `AuthManager::auth()` still refreshes when the access token expires within 5 minutes or the last refresh is older than 8 days.
- `persist_tokens` writes rotated tokens to `auth.json` in `CODEX_HOME`, which is the isolated home for inactive reads.

Control probe:

- The original probe produced `complete_response_ids: [1, 2]` and never received the `account/rateLimits/read` response id before the process exited after about 1.18 seconds.
- The corrected probe kept stdin/session alive after sending `account/rateLimits/read`, then waited for the rate-limit response id or timeout.
- Across the visible saved account catalog, isolated `CODEX_HOME` reads returned account metadata plus complete session and weekly windows.

### Refresh Semantics

For inactive saved catalog accounts:

- read each saved snapshot from the local catalog and seed a temporary isolated `CODEX_HOME/auth.json`;
- send `initialize`, `initialized`, `account/read`, and `account/rateLimits/read`;
- send `account/read` with `refreshToken: false`;
- keep stdin/session open until rate limits arrive or a timeout fires;
- write rotated isolated auth back to the same saved account only on an exact stable or scoped account id match;
- prefer complete `result.rateLimitsByLimitId["codex"]` values over `result.rateLimits`;
- preserve previous meaningful rate-limit windows on failed, missing, partial, zeroed, or suspicious isolated reads;
- never mutate the live local `~/.codex/auth.json`.

The safest status source remains `codex app-server` launched as a short-lived child process with isolated `CODEX_HOME`, because it works for account identity, plan, and complete rate-limit windows without mutating live auth.

### Follow-Up Trigger

Revisit this path if Codex changes the app-server protocol shape.

## Active Local Snapshot Relinking

Status: `accepted for active local refresh`

Date: 2026-05-06

### Decision

When refreshing the active local account, CodexPill may relink that saved account's snapshot from the current live local auth if the resolved Codex account identity is the same but the auth fingerprint changed.

This handles the case where the user signs back into Codex outside CodexPill. The saved catalog entry still represents the same account, but the saved auth snapshot can contain a revoked refresh token. Relinking the active saved snapshot keeps later switches from restoring stale auth.

### Refresh Semantics

For the active local account:

- read current account identity and rate-limit status from the local Codex app-server;
- resolve the returned identity to exactly one saved account;
- if current live auth has a different fingerprint for that same saved account, overwrite that saved account's snapshot with current live auth;
- preserve the saved account id and catalog position;
- then apply returned email, plan, and rate-limit metadata as normal.

For inactive saved accounts, CodexPill must keep using isolated saved-account status reads with `refreshToken: false` and must not rotate inactive snapshots through the real local auth file. When Codex rotates tokens inside the isolated home anyway, CodexPill writes them back to that account's snapshot only on an exact stable or scoped account id match, and discards them otherwise.
