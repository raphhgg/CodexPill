# Discovery: Usage Resets

## Product / Area Intent

Usage Resets extend CodexPill's account and rate-limit visibility with the reset availability surfaced by Codex app-server.

The feature helps a user keep working when the active local Codex account reaches an eligible rate limit. V1 should make reset availability visible without changing CodexPill's account ranking, notification, or remote-host mutation model.

## Audience / Users

- macOS Codex power users who already rely on CodexPill to choose which saved account to use.
- Users who hit Codex rate limits and need to know whether the current account has a manual recovery option.
- Users with remote hosts who need visibility into remote target state, but should not trigger account-wide mutations remotely in V1.

## Domain Model Summary

- `Usage reset` is the user-facing term for an available Codex rate-limit reset.
- `Reset Usage` is the user-facing action.
- `rateLimitResetCredits` is an app-server contract term and should remain inside the Codex integration boundary.
- A usage reset is not the same as workspace credits, monthly credit limits, token usage history, or a rate-limit window.
- An account with a usage reset available is still exhausted until the user explicitly resets usage and Codex confirms refreshed limits.

## Feature Map

### Active Local Account

- Show `Usage reset: 1 available` or `Usage resets: N available` on the active account card when the active local app-server snapshot reports resets available.
- Place the row directly below Session and Weekly limit rows, left-aligned with the other status labels.
- Show `Reset Usage on This Mac...` only when reset availability is known and a displayed Session or Weekly window is at 100%.
- Confirm before consuming a reset.
- Refresh rate limits immediately after every consume outcome.

### Remote Active Accounts

- Show reset availability for verified remote active accounts when the remote app-server refresh returns it.
- Do not expose a remote `Reset Usage` action in V1.
- Keep remote reset mutation deferred because the action likely affects account-wide state, not just one host.

### Inactive Saved Accounts

- Do not add reset availability to compact saved-account rows.
- Show reset availability only inside the account submenu as disabled informational text when known.
- Do not expose reset actions for inactive saved accounts in V1.

### Unsupported Codex Versions

- Feature-detect reset support from app-server responses and method behavior.
- If `rateLimitResetCredits` is missing or `null`, silently omit reset availability UI.
- If the consume method is unsupported, hide reset actions.
- Diagnostics may include only redacted capability flags, not raw app-server payloads.

## Key Workflows

### See Local Reset Availability

1. CodexPill refreshes the active local account through Codex app-server.
2. The response includes `rateLimitResetCredits.availableCount`.
3. If the count is greater than zero, the active card shows `Usage reset: 1 available` or `Usage resets: N available`.
4. If the count is zero, missing, or unsupported, the row is omitted.

### Reset Local Usage

1. The active local account has at least one usage reset available.
2. A displayed Session or Weekly window is at 100%.
3. The account submenu exposes `Reset Usage on This Mac...`.
4. The user confirms the action.
5. CodexPill calls `account/rateLimitResetCredit/consume` with a caller-generated idempotency key.
6. CodexPill shows the outcome status and refetches account rate limits.

### Inspect Inactive Account Reset Availability

1. CodexPill refreshes inactive saved accounts through isolated app-server reads.
2. When reset availability is returned, the saved account submenu shows `Usage reset: 1 available` or `Usage resets: N available`.
3. No reset action is offered for inactive accounts.

## Confirmation And Outcome Copy

Confirmation should mirror Codex App language:

- Title: `Do you want to reset your usage?`
- Body: `Keep working uninterrupted when you reset your rate limits. You have 1 reset available.`
- Primary action: `Reset Usage`
- Cancel action: `Cancel`

Outcome status copy:

- `reset`: `Usage reset. Refreshing limits...`
- `nothingToReset`: `No eligible usage to reset.`
- `noCredit`: `No usage resets available.`
- `alreadyRedeemed`: `Usage reset already applied. Refreshing limits...`

CodexPill should never optimistically decrement reset availability or reset local bars. The backend remains authoritative.

## Riskiest Assumptions

- A displayed 100% Session or Weekly window is a good enough proxy for showing the reset action in V1.
- `rateLimitResetCredits.availableCount` is account-level, not per-host, and can affect all targets using the same Codex account.
- Remote app-server reset consumption would be technically possible but product-risky because it mutates scarce account state from a host-oriented surface.
- `nothingToReset` can occur even when CodexPill believed an action looked useful, so the UI must handle it calmly.
- The count returned from isolated inactive-account reads is safe to display, but not safe enough to spend in V1.

## Validation Needed Before Planning

- Confirm local active account reads decode `rateLimitResetCredits.availableCount` from `codex-cli >= 0.141.0`.
- Confirm older Codex versions omit the UI cleanly when the field or consume method is unavailable.
- Confirm the consume method returns the expected outcome strings: `reset`, `nothingToReset`, `noCredit`, and `alreadyRedeemed`.
- Confirm idempotency-key handling: generate one key per logical reset attempt and reuse it only for retrying that same attempt.
- Confirm refresh-after-consume updates Session and Weekly windows without local optimistic mutation.
- Confirm remote display works without exposing a remote reset action.
- Confirm diagnostics and logs do not include raw app-server payloads, auth values, account identifiers, hostnames, or local paths.

## Out Of Scope For Now

- Remote `Reset Usage` actions.
- Inactive saved-account reset actions.
- Ranking exhausted accounts higher because they have usage resets available.
- Treating usage resets as notification availability.
- Status-bar reset indicators.
- Automatic reset consumption.
- Showing zero-reset rows in active cards or compact saved-account rows.
- Backend scraping, browser dashboard scraping, hidden WebViews, or any non-app-server reset source.

## Open Questions

- Should the active-card row use `Usage reset: 1 available` only, or should it include a compact icon later?
- Should the reset action require a second confirmation every time, or can recent confirmations be remembered for the app session?
- Should CodexPill eventually introduce a `recoverable` availability state for exhausted accounts with resets available?
- Should remote reset consumption get a separate prototype before refinement?
- Should account submenu reset availability appear above or below the `In use on:` row?

## Recommended Next Checkpoint

Refine a focused Accounts feature contract before implementation. The likely destination is `docs/features/accounts/06-usage-resets.md`.

Before creating implementation slices, decide whether the remaining open questions are small enough for refinement or whether remote reset consumption needs its own prototype brief.
