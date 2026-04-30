# Refresh Accounts

## Isolated Saved-Account Status Reads

Status: `accepted for inactive local catalog refresh`

Issue: `RGR-140`

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
- Session limit read: no.
- Weekly limit read: no.
- Live local auth changed: no. The live `~/.codex/auth.json` hash, size, and modification time were unchanged before and after the isolated probe.
- App-server process behavior: a child `codex app-server` process was launched by the probe and exited without probe termination. Existing app-server process count was unchanged before and after the probe.
- Temporary state cleanup: the isolated root was removed after the probe.
- Secret handling: no auth payloads, tokens, device codes, raw snapshots, account identifiers, or email addresses were printed or committed.

Control probe:

- Running the same app-server request sequence against the normal live Codex home also returned account identity and plan but did not return a rate-limit response.
- That means the missing limit proof is not enough to reject isolated `CODEX_HOME`; it is a current status-source gap for this Codex executable and protocol surface.

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
