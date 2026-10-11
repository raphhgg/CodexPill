# Codex Reset Credits

See how many Codex limit resets the active account has, when the next one expires, and use one.

## Data Contract

- Source: `account/rateLimits/read` on the local Codex app-server, field `rateLimitResetCredits`.
- Codex sends `availableCount` and a `credits` list with one `expiresAt` per credit (`null` for a credit that never expires). The list can be shorter than the count.
- Refill keeps the count and the expiry of each listed credit with status `available`, as `UsageSnapshot.resetCredits`. `nextExpiry` is the earliest of those dates.
- `credits: null` means Codex knows only the count. Refill keeps `credits` as `nil` and shows the count without a date.
- Codex versions without the field keep working. `resetCredits` stays `nil` and nothing about resets is shown.
- The last known count and expiries are saved with the account, like its limits.

## Using A Reset

- `account/rateLimitResetCredit/consume` spends one credit on the live account the local Codex app-server runs as, so it applies only to the active local account.
- Each attempt sends one idempotency key. Refill keeps one key per saved account and reuses it when the call fails or Codex returns an outcome it does not know, so a retry cannot spend a second credit. It starts a new key once Codex answers.
- After a reset, Refill refreshes the active account's limits.
- Switching accounts waits until the reset and that refresh finish. A switch asked for meanwhile shows "Reset in progress" instead of switching.

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
