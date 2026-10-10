# Codex Reset Credits

See how many Codex limit resets the active account has, when the next one expires, and use one.

## Data Contract

- Source: `account/rateLimits/read` on the local Codex app-server, field `rateLimitResetCredits`.
- CodexPill keeps `availableCount` and the earliest `expiresAt` among credits with status `available`, as `UsageSnapshot.resetCredits`. Credits that never expire do not set the date.
- `credits: null` means Codex knows only the count. CodexPill shows the count without a date.
- Codex versions without the field keep working. `resetCredits` stays `nil` and nothing about resets is shown.
- The last known count and date are saved with the account, like its limits.

## Using A Reset

- `account/rateLimitResetCredit/consume` spends one credit on the live account the local Codex app-server runs as, so it applies only to the active local account.
- Each attempt sends one idempotency key. CodexPill reuses it when the call fails or Codex returns an outcome it does not know, so a retry cannot spend a second credit. It starts a new key once Codex answers.
- After a reset, CodexPill refreshes the active account's limits.

| Codex outcome | Message |
|---|---|
| `reset`, `alreadyRedeemed` | Your Codex limits are reset. |
| `nothingToReset` | Nothing to reset right now. Your reset is still available. |
| `noCredit` | No resets left on this account. |
| unknown outcome | Codex didn't confirm the reset. Check your limits before trying again. |
| call failed | Couldn't use a reset. Try again. |

## Status

The data layer and the consume action ship first. The menu row ("2 resets available · Next expires 5 Nov") and a confirmed `Use a Reset…` item follow with the chosen menu design.

## Validation

Tests never spend a real credit. Platform tests run the consume call against a stand-in `codex app-server` script. `AccountsController` tests use an in-memory reset-credit client.
