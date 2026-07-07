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

## Acceptance Criteria

- Inactive saved accounts refresh through isolated app-server reads without
  mutating live local Codex auth.
- Failed, missing, partial, zeroed, or suspicious isolated reads preserve
  previous meaningful rate-limit data.
- Active local refresh relinks the saved snapshot from current live auth when
  the returned identity is the same saved account and the auth fingerprint
  changed.
- Active local refresh does not relink when identity is ambiguous or different.

## Validation Scenario Candidates

- `refresh-inactive-isolated-status`
- `refresh-active-relinks-same-account`

## Validation Intent

Feature risk: `parser`, `auth_isolation`, `state_truth`, `privacy`

Primary proof for `refresh-inactive-isolated-status`:
`contract-fixture`

Supporting proof for `refresh-inactive-isolated-status`: `integration`

Primary proof for `refresh-active-relinks-same-account`: `unit`

Product scenarios:

- `refresh-inactive-isolated-status` proves that inactive saved accounts refresh
  through isolated saved-account app-server reads, live local auth remains
  unchanged, previous meaningful rate-limit windows are preserved when isolated
  reads fail or return unusable data, and temporary isolated `CODEX_HOME` state
  is shaped and cleaned up as expected.
- `refresh-active-relinks-same-account` proves that active local refresh relinks
  the saved snapshot only when the current live identity resolves to the same
  saved account with a changed auth fingerprint, and refuses ambiguous or
  different identities before overwriting saved snapshots.

Required evidence:

- focused suite output from `HydrateSavedAccountsMetadataUseCaseTests`,
  `CodexAppServerClientTests`, and `AppPathsTests`;
- Kite scenario receipt for `refresh-inactive-isolated-status`.
- for active relink, focused suite output from
  `RefreshActiveAccountUseCaseTests` and `CodexAccountMatcherTests`;
- Kite scenario receipt for `refresh-active-relinks-same-account`.

Non-claims:

- The inactive refresh scenario does not prove live Codex app-server execution
  with real saved accounts, real auth snapshots, tokens, account identifiers,
  emails, hostnames, private paths, remote inactive-account refresh, menu
  projection, or live macOS menu-bar behavior.
- The active relink scenario does not prove live Codex app-server execution,
  real auth snapshots, remote install or switch preflight relink, menu
  projection, or live macOS menu-bar behavior.

Live opt-in: not required for this scenario.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Inactive saved accounts refresh through isolated app-server reads without mutating live auth. | `contract-fixture` plus `integration` | `make verify-refresh-inactive-isolated-status-scenario` running `HydrateSavedAccountsMetadataUseCaseTests`, `CodexAppServerClientTests`, and `AppPathsTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | The isolated read sends the expected app-server sequence, updates metadata/rate limits when complete, removes temporary state, and leaves live local auth data unchanged. | Fake auth snapshots, temporary isolated `CODEX_HOME`, and synthetic app-server payloads only; artifacts must not include raw auth JSON, tokens, private paths, account identifiers, emails, or hostnames. |
| Failed or suspicious inactive reads preserve meaningful previous limits. | `contract-fixture` plus `integration` | `make verify-refresh-inactive-isolated-status-scenario` running focused failed, missing, and suspicious isolated read fixtures. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Previous meaningful session/weekly windows remain authoritative when the isolated read fails, omits rate limits, or returns suspicious zeroed limits, and the menu does not present suspicious data as fresh truth. | Synthetic payloads only; no raw app-server output from real accounts. |
| Active local refresh relinks the same account when the auth fingerprint changed. | `unit` | `make verify-refresh-active-relinks-same-account-scenario` running `RefreshActiveAccountUseCaseTests` and `CodexAccountMatcherTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Matching identity with changed fingerprint overwrites that saved account's snapshot, preserves saved account id/display name/catalog position, and applies returned metadata/rate limits according to refresh rules. | Fake live auth and synthetic identity data only; no raw auth payloads, tokens, private paths, real emails, hostnames, or stable account identifiers. |
| Active local refresh refuses ambiguous or different identity relinks. | `unit` | `make verify-refresh-active-relinks-same-account-scenario` running active refresh ambiguity/no-match and matcher tests. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Ambiguous or different returned identity does not call the snapshot relinker, does not persist catalog changes, and surfaces recoverable refresh failure state. | Synthetic identity fixtures only; no raw account, auth, token, path, email, or hostname data. |

## Validation Targets

- Contract fixtures for complete and partial app-server status payloads.
- Integration tests proving inactive isolated reads do not mutate live local
  auth.
- Integration tests for preserving previous meaningful rate-limit windows on
  failed or suspicious reads.
- Active-refresh tests for same-identity relinking and ambiguous/different
  identity refusal.
- Privacy review confirming refresh artifacts do not print auth payloads,
  tokens, account identifiers, emails, hostnames, or private paths.
