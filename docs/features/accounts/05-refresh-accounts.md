# Refresh Accounts

## Spike Result: Isolated Saved-Account Status Reads

Status: `inconclusive`

Issue: `RGR-140`

Date: 2026-04-30

### Decision

Do not implement scheduled inactive saved-account refresh yet.

The isolated saved-account read shape is promising for non-secret account metadata, but the current proof did not return session or weekly rate-limit windows. CodexPill should keep preserving previous meaningful rate-limit data for inactive saved accounts until a Codex status source reliably returns complete limit data from isolated state.

### Evidence

Sanitized manual probe:

- Codex executable: `/Applications/Codex.app/Contents/Resources/codex`
- Codex version: `codex-cli 0.126.0-alpha.8`
- Isolated environment: temporary `CODEX_HOME` directory named with the `CodexPill-CODEX_HOME-spike-<random>` prefix, seeded only with a saved snapshot copied to `auth.json`, with a `tmp` subdirectory and `TMPDIR` scoped to that isolated root.
- Saved catalog shape observed: 10 saved accounts and 10 saved snapshots.
- Status source: `codex app-server` over stdio with `initialize`, `account/read`, and `account/rateLimits/read` requests.
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

### Recommended Path

Keep the current `Refresh Time` behavior limited to surfaces that already have reliable status reads: the active local account and configured remote hosts.

For inactive saved catalog accounts:

- show and preserve the last meaningful saved rate-limit data;
- do not overwrite meaningful limits with partial, missing, zeroed, or suspicious isolated results;
- avoid background live-auth switch-and-restore;
- defer scheduled inactive saved-account refresh until a follow-up spike or Codex update proves complete isolated reads for identity, plan, session limits, and weekly limits.

The safest candidate status source remains `codex app-server` launched as a short-lived child process with isolated `CODEX_HOME`, because it already works for account identity and plan without mutating live auth. It is not accepted for scheduled full-catalog refresh until `account/rateLimits/read` returns complete primary and secondary windows in isolated mode.

### Follow-Up Trigger

Create the ready-for-agent implementation issue only after one of these is true:

- `codex app-server` returns complete `account/rateLimits/read` data from isolated `CODEX_HOME`;
- another Codex-supported status command returns account identity, plan, session limits, and weekly limits from isolated `CODEX_HOME`;
- product direction explicitly accepts a metadata-only inactive-account refresh that leaves previous rate-limit data untouched.
