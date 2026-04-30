# Refresh Accounts

## Spike Result: Isolated Saved-Account Status Reads

Status: `accepted`

Issue: `RGR-140`

Date: 2026-04-30

### Decision

Implement inactive saved-account refresh through isolated saved-account status reads.

The original RGR-140 probe was inconclusive because it closed the app-server stdin/session before the asynchronous rate-limit response arrived. A corrected follow-up probe kept the session open until the `account/rateLimits/read` response id arrived or timed out, and proved that CodexPill can read account identity, plan, session limits, and weekly limits for saved catalog accounts from isolated temporary `CODEX_HOME` directories without mutating live local auth.

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
- The corrected probe kept stdin/session alive after sending `account/rateLimits/read`, then waited for response id `3` or timeout.
- Across the visible saved account catalog, isolated `CODEX_HOME` reads returned account metadata plus complete session and weekly windows.

### Recommended Path

Extend `Refresh Time` for inactive saved catalog accounts with isolated saved-account status reads.

For inactive saved catalog accounts:

- iterate saved catalog accounts on refresh;
- create a temporary isolated `CODEX_HOME` for each account;
- copy the saved snapshot to isolated `auth.json`;
- run `/Applications/Codex.app/Contents/Resources/codex app-server`;
- send `initialize`, `initialized`, `account/read`, and `account/rateLimits/read`;
- keep stdin/session open until the rate-limit response arrives or timeout fires;
- prefer `rateLimitsByLimitId["codex"]` when present and complete, with `rateLimits` as fallback;
- do not overwrite meaningful limits with partial, missing, zeroed, or suspicious isolated results;
- rebuild the menu after catalog refresh;
- avoid background live-auth switch-and-restore.

The safest accepted status source is `codex app-server` launched as a short-lived child process with isolated `CODEX_HOME`, because it reads the full local account status surface without changing the user's live Codex auth state.

### Follow-Up Trigger

Ready-for-agent implementation issue: `RGR-141`.

The implementation must include regression coverage for the corrected app-server session behavior: a missing rate-limit response from a prematurely closed session is a probe failure, not proof that isolated reads are unavailable.
