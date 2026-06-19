# Usage Resets

## User Story

As a CodexPill user whose active local Codex account has reached a rate limit, I want to see when a usage reset is available and reset my local usage deliberately, so I can keep working without switching accounts.

## Product Contract

Usage Resets are an Accounts feature that extends CodexPill's existing app-server rate-limit surface.

CodexPill uses Codex App-style user-facing language:

- `Usage reset` for reset availability.
- `Reset Usage` for the action.

Codex app-server contract names such as `rateLimitResetCredits` stay inside the Codex integration boundary and must not become UI copy.

V1 behavior:

- Show reset availability when Codex app-server returns `rateLimitResetCredits.availableCount > 0`.
- Omit reset availability when the field is missing, `null`, zero, or unsupported by the running Codex version.
- Allow reset consumption only for the active local account.
- Show the local reset action only when reset availability is greater than zero and at least one displayed Session or Weekly window is at 100%.
- Require confirmation every time before consuming a usage reset.
- Refresh account rate limits after every consume outcome.
- Never optimistically decrement usage reset availability or reset local usage bars.
- Do not change account availability ranking or notification behavior based on usage reset availability in V1.
- Do not expose remote or inactive saved-account reset actions in V1.

## Happy Path

1. CodexPill refreshes the active local account through Codex app-server.
2. Codex app-server returns `rateLimitResetCredits.availableCount` with a value greater than zero.
3. The active local account card shows `Usage reset: 1 available` or `Usage resets: N available` below Session and Weekly limits.
4. A displayed Session or Weekly limit reaches 100%.
5. The active account submenu exposes `Reset Usage on This Mac...`.
6. The user chooses the action.
7. CodexPill shows a confirmation alert.
8. The user confirms with `Reset Usage`.
9. CodexPill calls the app-server consume method with an idempotency key for this logical reset attempt.
10. CodexPill shows outcome status copy and refreshes rate limits from Codex app-server.
11. The menu reflects the refreshed app-server snapshot.

## UI / Copy / States

### Active Account Card

Place the usage reset row directly below Session and Weekly limit rows and before Token Usage or any divider.

Examples:

```text
Session        100%  Resets in 1h
Weekly         64%   Resets Tuesday
Usage reset: 1 available
```

```text
Session        100%  Resets in 1h
Weekly         100%  Resets Tuesday
Usage resets: 2 available
```

The row is informational, left-aligned with the other status labels, and not clickable.

For a combined local and remote active card such as `This Mac + workstation`, the usage reset row follows the same source as the displayed limit values. Current Accounts behavior says combined cards show local current-account limits, so the usage reset row is local too.

### Account Submenu

For accounts with known reset availability, show a disabled informational row above switch actions:

```text
name@example.com
In use on: This Mac
Usage reset: 1 available
Reset Usage on This Mac...
Switch on workstation
Rename...
Remove...
```

For inactive saved accounts:

```text
name@example.com
In use on: Not active
Usage reset: 1 available
Switch on This Mac
Rename...
Remove...
```

Inactive saved accounts do not expose `Reset Usage` actions in V1.

### Reset Action

Show `Reset Usage on This Mac...` only when:

- the account is the active local account;
- `availableCount > 0`; and
- at least one displayed Session or Weekly window is at 100%.

Do not show disabled remote reset actions in V1. Remote reset consumption is deferred instead of teased.

### Confirmation

Title:

```text
Do you want to reset your usage?
```

Body for one reset:

```text
Keep working uninterrupted when you reset your rate limits. You have 1 reset available.
```

Body for multiple resets:

```text
Keep working uninterrupted when you reset your rate limits. You have N resets available.
```

Actions:

```text
Cancel
Reset Usage
```

Confirmation is required every time. V1 does not remember confirmation for the app session and does not offer a "do not ask again" path.

### Outcome Status

- `reset`: `Usage reset. Refreshing limits...`
- `nothingToReset`: `No eligible usage to reset.`
- `noCredit`: `No usage resets available.`
- `alreadyRedeemed`: `Usage reset already applied. Refreshing limits...`

Transport, auth, timeout, or unsupported-method failures use the existing Codex app-server failure surface. CodexPill should not locally infer that a reset was spent when the backend response is unavailable.

## Edge Cases

- Codex version does not include `rateLimitResetCredits`.
- Codex version includes reset availability but not the consume method.
- `rateLimitResetCredits` is present but `null`.
- `availableCount` is zero.
- `availableCount` is greater than zero, but no displayed Session or Weekly window is at 100%.
- The active local account has no complete rate-limit windows.
- The active card is combined with one or more verified remote hosts.
- A verified remote active account reports reset availability.
- An inactive saved account reports reset availability through an isolated app-server read.
- App-server returns `nothingToReset` after CodexPill showed the reset action.
- App-server returns `noCredit` because reset availability changed after the menu rendered.
- The same reset attempt is retried with the same idempotency key and returns `alreadyRedeemed`.
- The consume request times out or app-server exits before responding.
- Refresh after consume fails.
- Diagnostics are exported after reset availability or reset outcome states were observed.

## Acceptance Criteria

### Active Card Shows Usage Reset Availability

Given the active local app-server snapshot reports `availableCount > 0`, when the menu renders the active local account card, then CodexPill shows `Usage reset: 1 available` or `Usage resets: N available` below the Session and Weekly limit rows.

### Active Card Omits Unsupported Or Empty Availability

Given reset availability is missing, `null`, unsupported, or zero, when the menu renders an active account card, then CodexPill omits the usage reset row.

### Local Reset Action Appears Only When Useful

Given the active local account has `availableCount > 0` and a displayed Session or Weekly window is at 100%, when the user opens the account submenu, then CodexPill shows `Reset Usage on This Mac...`.

### Local Reset Action Is Hidden When Not Useful

Given the active local account has reset availability but no displayed Session or Weekly window is at 100%, when the user opens the account submenu, then CodexPill does not show `Reset Usage on This Mac...`.

### Reset Requires Confirmation

Given the user chooses `Reset Usage on This Mac...`, when the action starts, then CodexPill asks for confirmation before calling Codex app-server to consume a usage reset.

### Reset Outcome Refreshes Limits

Given Codex app-server returns any consume outcome, when CodexPill receives the outcome, then CodexPill shows the matching outcome status and refetches account rate limits.

### Reset Does Not Optimistically Mutate UI

Given the user confirms reset usage, when the consume request is in flight, then CodexPill does not locally decrement reset availability or reset Session or Weekly bars before a refreshed app-server snapshot arrives.

### Inactive Saved Account Shows Availability Only In Submenu

Given an inactive saved account has known reset availability, when the saved account appears in compact account rows, then the compact row does not show usage reset availability; when the account submenu opens, then the submenu shows a disabled `Usage reset: N available` row above switch actions.

### Remote Reset Action Is Deferred

Given a verified remote active account reports reset availability, when the user opens the remote account submenu, then CodexPill may show reset availability but does not expose a remote `Reset Usage` action.

### Availability Ranking Is Unchanged

Given an exhausted account has usage resets available, when CodexPill ranks saved account availability or fires availability notifications, then usage reset availability does not make that account count as currently available.

### Diagnostics Stay Redacted

Given diagnostics are exported, when reset support or reset outcome information is included, then diagnostics include only redacted capability or result categories and never raw app-server payloads, auth values, account identifiers, hostnames, local paths, or tokens.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Active Card Shows Usage Reset Availability | deterministic-ui | `make test` with menu presentation/projection coverage | `build/results/local/CodexPill.xcresult`; deterministic menu/card projection assertions | Active local card projection includes `Usage reset: 1 available` or plural `Usage resets: N available` below Session and Weekly rows | Use synthetic accounts only; no raw app-server payloads or real account identifiers in assertions |
| Active Card Omits Unsupported Or Empty Availability | deterministic-ui, contract-fixture | `make test` with parser fixtures and menu projection coverage | Parser fixture assertions; menu/card projection assertions | Missing, `null`, unsupported, and zero reset availability decode without failure and render no usage reset row | Fixture payloads must be synthetic and must not include auth material |
| Local Reset Action Appears Only When Useful | deterministic-ui | `make test` with menu builder coverage | Account submenu projection assertions | Active local account submenu includes `Reset Usage on This Mac...` only when reset count is greater than zero and a displayed Session or Weekly window is at 100% | Synthetic account labels only |
| Local Reset Action Is Hidden When Not Useful | deterministic-ui | `make test` with menu builder matrix coverage | Account submenu projection assertions | Reset action is absent for zero/missing availability, non-100% windows, inactive accounts, and remote-only accounts | Synthetic account labels only |
| Reset Requires Confirmation | workflow-event-log, deterministic-ui | `make test` with workflow fake and alert/confirmation coverage | Structured fake-client call log; confirmation decision log; alert copy assertions | Consume is not called before confirmation; cancel produces no consume call; confirm produces exactly one consume attempt | Do not log raw auth, account IDs, hostnames, or app-server payload bodies |
| Reset Outcome Refreshes Limits | workflow-event-log | `make test` with fake app-server outcome matrix | Structured fake-client call sequence and status-copy assertions | Each consume outcome records matching status copy and triggers a rate-limit refresh after the consume result | Outcome artifacts include result categories only, not raw backend payloads |
| Reset Does Not Optimistically Mutate UI | workflow-event-log, deterministic-ui | `make test` with in-flight workflow and menu projection coverage | Event log plus before/after menu projection assertions | In-flight state does not decrement reset count or reset Session/Weekly bars before a refreshed app-server snapshot arrives | Synthetic account and rate-limit values only |
| Inactive Saved Account Shows Availability Only In Submenu | deterministic-ui | `make test` with compact row and submenu projection coverage | Compact row projection; submenu projection | Compact saved-account rows omit usage reset availability; inactive submenu shows disabled `Usage reset: N available` above switch actions | Synthetic account labels only |
| Remote Reset Action Is Deferred | deterministic-ui | `make test` with remote account menu projection coverage | Remote submenu projection assertions | Remote reset availability may be displayed, but no remote `Reset Usage` action is exposed | Synthetic host labels only; no real hostnames |
| Availability Ranking Is Unchanged | unit, integration | `make test` with account availability and notification coverage | Account availability ordering assertions; notification workflow assertions | Reset availability does not make exhausted accounts rank as available and does not trigger availability notifications | Synthetic accounts only |
| Diagnostics Stay Redacted | diagnostics-export | `make test` with diagnostics export coverage | Redacted diagnostics fixture/export assertions | Diagnostics include only allowlisted support/result categories and omit raw payloads, auth values, account identifiers, hostnames, paths, and tokens | Redaction is a negative proof requirement; no real diagnostics artifacts may be committed |

## Validation Targets

- App-server parser tests for `rateLimitResetCredits.availableCount`.
- App-server parser tests for missing, `null`, and zero reset availability.
- App-server consume response tests for `reset`, `nothingToReset`, `noCredit`, and `alreadyRedeemed`.
- UI presentation tests for active-card usage reset rows.
- Menu builder tests for showing and hiding `Reset Usage on This Mac...`.
- Menu builder tests for inactive saved-account submenu placement.
- Workflow tests proving confirmation gates consume.
- Workflow tests proving consume outcomes trigger refresh and do not optimistically mutate local usage state.
- Compatibility tests or fixtures for older Codex app-server payloads.
- Remote presentation tests proving remote display can exist without remote reset action.
- Account availability tests proving reset availability does not affect ranking or notifications.
- Diagnostics tests proving only redacted capability/result categories are exported.
- Manual QA with Codex `0.141.0+` and an older/fixture app-server payload.

## Candidate Execution Slices

### Decode And Store Usage Reset Availability

Purpose:

Extend the Codex app-server rate-limit boundary and account model so reset availability can be carried through existing refresh flows.

Acceptance:

- Local, isolated saved-account, and remote refresh paths preserve `availableCount` when returned.
- Older payloads continue to decode and render without reset UI.
- Diagnostics stay redacted.

Proof Contract:

| Acceptance | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Preserve returned availability through refresh paths | contract-fixture, integration | `make test` with parser, mapper, refresh, and remote status fixtures | `CodexAppServerParserTests`, account refresh tests, remote status or rate-limit resolution tests, and `build/results/local/CodexPill.xcresult` | `availableCount > 0` survives app-server DTO decoding into the internal account/rate-limit model for local, isolated saved-account, and remote refresh surfaces | Fixtures use synthetic payloads and accounts only |
| Older, missing, `null`, and zero availability remain compatible | contract-fixture | `make test` with app-server payload fixtures | Parser fixture assertions | Older payloads decode without failure; missing, `null`, and zero availability produce no usage reset availability in the internal model | Do not include raw real app-server payloads |
| Diagnostics stay redacted | diagnostics-export | `make test` with diagnostics builder coverage | Redacted diagnostics export fixture/assertions | Diagnostics expose only redacted capability/result categories for reset support or outcomes and never raw app-server payloads, auth values, account identifiers, hostnames, paths, or tokens | Redaction assertions must be explicit negative proof |

Required Artifacts:

- `build/results/local/CodexPill.xcresult`.
- Synthetic app-server rate-limit fixture cases for positive, missing, `null`, and zero `rateLimitResetCredits`.
- Diagnostic export assertions or fixture output when diagnostics are touched.
- No visual proof is required for this slice.

Degraded Proof Rules:

- If `make test` cannot run, focused parser/model tests can partially prove the slice, but refresh-path propagation and diagnostics redaction must be marked unproven.
- If diagnostics are not touched in this slice, record diagnostics proof as not applicable rather than silently omitting the privacy requirement from later slices.

### Render Usage Reset Availability

Purpose:

Show reset availability in active cards and account submenus without changing actions or account ranking.

Acceptance:

- Active local and verified remote cards show the usage reset row only when count is greater than zero.
- Inactive saved-account submenus show reset availability above switch actions.
- Compact account rows, status bar, notifications, and ranking remain unchanged.

Proof Contract:

| Acceptance | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Active and verified remote cards show usage reset rows only when count is greater than zero | deterministic-ui | `make test` with menu/card presentation fixtures | Menu/card projection assertions and `build/results/local/CodexPill.xcresult` | Projection shows singular/plural usage reset copy in the specified placement for count greater than zero and omits it for unsupported, `null`, missing, or zero states | Use synthetic accounts and hosts only |
| Inactive saved-account submenus show availability above switch actions | deterministic-ui | `make test` with menu builder fixtures | Submenu projection assertions | Disabled `Usage reset: N available` row appears above switch actions for inactive accounts with known availability | Use synthetic account labels only |
| Compact rows, status bar, notifications, and ranking remain unchanged | unit, deterministic-ui, integration | `make test` with compact row, status bar, account availability, and notification coverage | Projection, ranking, and notification assertions | Reset availability is absent from compact rows/status bar and does not affect ranking or notification behavior | Synthetic fixture data only |

Required Artifacts:

- `build/results/local/CodexPill.xcresult`.
- Deterministic menu/card projection assertions for active, inactive, remote, missing, zero, and plural states.
- Ranking and notification regression assertions.
- Screenshot smoke is optional and secondary; deterministic projection is the owning proof.

Degraded Proof Rules:

- If deterministic menu projection is unavailable, this slice is not harness-ready.
- If live app launch or screenshot QA is unavailable, the slice may still pass with deterministic projection proof, but handoff must state that live visual smoke was not run.

### Consume Local Usage Reset

Purpose:

Add the explicit local active-account `Reset Usage on This Mac...` flow.

Acceptance:

- The action appears only for the active local account when a reset is available and a displayed limit is at 100%.
- The action always asks for confirmation.
- The consume request uses an idempotency key per logical attempt.
- All consume outcomes show the specified status copy and refetch limits.
- The UI does not optimistically decrement or reset local values.

Proof Contract:

| Acceptance | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Action appears only for eligible active local account | deterministic-ui | `make test` with menu builder eligibility matrix | Account submenu projection assertions | `Reset Usage on This Mac...` appears only for active local accounts with reset availability and at least one displayed 100% Session or Weekly window | Synthetic accounts only |
| Confirmation always gates consume | workflow-event-log, deterministic-ui | `make test` with fake confirmation controller and consume client | Confirmation decision log; fake consume client call log; alert copy assertions | Cancel produces no consume call; confirm produces one consume attempt after confirmation; no session memory or "do not ask again" path exists | Logs contain no auth, account IDs, paths, hostnames, or raw payloads |
| Consume uses idempotency key per logical attempt | workflow-event-log | `make test` with fake consume client | Fake consume request log | One stable idempotency key is used for retries of the same logical attempt; separate attempts use separate keys | Idempotency keys in tests are synthetic |
| Consume outcomes show copy and refetch limits | workflow-event-log | `make test` with consume outcome matrix | Fake app-server call sequence; status copy assertions; refresh call log | `reset`, `nothingToReset`, `noCredit`, and `alreadyRedeemed` map to specified copy and each outcome triggers rate-limit refresh | Outcome evidence stores categories only |
| UI does not optimistically mutate local values | workflow-event-log, deterministic-ui | `make test` with in-flight reset state and refreshed snapshot fixtures | Event log plus menu/card projection before and after refresh | Reset availability and Session/Weekly bars remain unchanged until refreshed app-server data is applied | Synthetic rate-limit values only |

Required Artifacts:

- `build/results/local/CodexPill.xcresult`.
- Fake confirmation decision log.
- Fake consume-client request log with idempotency-key assertions.
- Fake refresh call sequence after each consume outcome.
- Deterministic menu/card projection proving no optimistic mutation.

Degraded Proof Rules:

- If fake-client event logs cannot prove confirmation, consume, idempotency, refresh, and no-optimistic-mutation ordering, this slice is not harness-ready.
- Live manual QA may supplement this slice, but it cannot replace the fake workflow proof.
- If the running Codex app-server does not support consume, manual QA must use a fixture or be marked degraded; no real account reset should be attempted without explicit opt-in.

## Out Of Scope / Deferrals

- Remote `Reset Usage` actions.
- Inactive saved-account reset actions.
- Automatic reset consumption.
- Remembered confirmations or "do not ask again" behavior.
- Reset availability in the closed status bar.
- Reset availability in compact saved-account rows.
- Availability ranking changes based on reset availability.
- Notification behavior changes based on reset availability.
- A `recoverable` account availability state.
- Browser scraping, hidden WebViews, backend scraping, or non-app-server reset sources.

## Open Questions

- Should a future version introduce a `recoverable` account availability state for exhausted accounts with usage resets available?
- Should remote reset consumption get a separate prototype before refinement?
- Should the active-card row eventually include an icon, or remain plain text permanently?

## Recommended Next Checkpoint

If this contract is approved, create implementation slices directly from the candidate execution slices.

If remote reset consumption is promoted into scope later, run a separate discovery or prototype brief before adding it to this feature.
