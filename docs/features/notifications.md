# Notifications

Notifications owns notification preferences, macOS permission recovery, notification delivery copy, action buttons, and dedupe behavior.

## Entry Point

Notifications are configured from `Notifications` in the App Controls section.

## Menu Copy

Modes:

- `Account Available`: notify when the user previously had no usable saved account and one becomes usable again.
- `Current Runs Out`: notify when the current local or verified remote account is out and another saved account is ready.

Permission recovery:

- `Enable Notifications…` appears when app notification workflows are off or macOS notification permission needs recovery.

## Delivery Copy

`Current Runs Out` notifications should explain why they fired:

- Title pattern: `<Active Account> is out on <Target>`
- Body pattern: `<Limit summary>. <Fallback Account> is ready.`

`Account Available` notifications should keep the copy simple:

- Body pattern: `<Fallback Account> is available again`

## Actions

Notification actions should offer direct use targets when the platform supports it:

- `Use on This Mac`
- `Use on <remote host>`

If multiple direct actions do not fit cleanly, fall back to a single best-option action.

## Dedupe

After CodexPill notifies for a saved account, that account is suppressed until CodexPill observes it become active locally or on a verified remote host.
