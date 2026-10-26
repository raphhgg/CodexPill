# Codex Reset Credits

See how many Codex limit resets the signed-in account has, when the next one expires, and use one.

Reset credits are not the Codex credit balance. The balance has its own card line, described in [Accounts](accounts/00-accounts.md#credits).

## Data Contract

- Source: `account/rateLimits/read` on the local Codex app-server, field `rateLimitResetCredits`.
- Codex sends `availableCount` and a `credits` list with one `expiresAt` per credit (`null` for a credit that never expires). The list can be shorter than the count.
- rusage keeps the count and the expiry of each listed credit with status `available`, as `UsageSnapshot.resetCredits`. `nextExpiry` is the earliest of those dates.
- `credits: null` means Codex knows only the count. rusage keeps `credits` as `nil` and shows the count without a date.
- Codex versions without the field keep working. `resetCredits` stays `nil` and nothing about resets is shown.
- The last known count and expiries are kept in memory with the account, like its limits.

## Using A Reset

- `account/rateLimitResetCredit/consume` spends one credit on the live account the local Codex app-server runs as, so it applies only to the Codex account signed in on this Mac.
- Each attempt sends one idempotency key. rusage keeps the key until Codex answers and reuses it when the call fails or Codex returns an outcome it does not know, so a retry cannot spend a second credit.
- After a reset, rusage refreshes the account's limits.
- A reset and a sign-in never overlap. A reset is refused while a sign-in runs, and confirming a new sign-in during a reset shows "Reset in progress" instead.

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
