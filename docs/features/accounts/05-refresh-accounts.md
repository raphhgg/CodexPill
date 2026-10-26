# Refresh Accounts

## The Codex Account

Status: `accepted`

### Decision

rusage refreshes one Codex account: the one `auth.json` signs in to. There are no other Codex accounts to refresh and no isolated reads for them.

### Refresh Semantics

On the scheduled refresh tick, when the menu opens, after a sign-in, and after a reset:

- read `auth.json` and compare its fingerprint with the account rusage holds;
- when Codex rotated its tokens, keep the account and its last reading and take the new fingerprint;
- when `auth.json` names a different account, signed in outside rusage, replace the account and drop the old reading;
- when `auth.json` is missing, treat Codex as signed out and show no Codex card;
- read identity, plan, and limits from the local Codex app-server with `readCurrentAccountStatus` (`account/read`, then `account/rateLimits/read`), first with `refreshToken: false`, retrying with `refreshToken: true` when a read fails or comes back incomplete;
- prefer complete `result.rateLimitsByLimitId["codex"]` values over `result.rateLimits`;
- name each window by its length, never its field. A Free account returns one 30-day window as `secondary`; rusage shows it as `Monthly`;
- keep the last reading when a read fails or returns no usable windows;
- drop a reading that finishes after the sign-in changed, since it belongs to the old account.

The scheduled refresh skips Codex when its card is hidden, when Codex is signed out, or while a sign-in runs.

rusage never writes `auth.json` during a refresh. The only write is a sign-in the user confirmed. See [Sign In To Another Codex Account](01-add-account.md).

### Follow-Up Trigger

Revisit this path if Codex changes the app-server protocol shape or the `auth.json` format.
