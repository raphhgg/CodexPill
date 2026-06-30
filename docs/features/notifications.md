# Notifications

Notifications owns notification preferences, macOS permission recovery, notification delivery copy, action buttons, and dedupe behavior.

## Entry Point

Notifications are configured from `Notifications` in the App Controls section.

## Menu Copy

Modes:

- `Account Available`: notify when the user previously had no usable saved account and one becomes usable again.
- `Current Runs Out`: notify when the current local or verified remote account is out and another saved account is ready.

Permission recovery:

- CodexPill stores notification intent when the user toggles a mode on.
- If macOS notification permission is not determined, CodexPill asks for permission only when it is about to send the first real notification.
- If macOS notification permission is denied, the submenu shows `Enable in macOS Settings…`.
- While macOS permission is denied, `Account Available` and `Current Runs Out` appear unchecked and disabled without deleting the user's saved CodexPill notification preferences.

## Delivery Copy

`Current Runs Out` notifications should explain why they fired:

- Title pattern: `<Active Account> is out on <Target>`
- Body pattern: `<Limit summary>. <Fallback Account> is ready.`

`Account Available` notifications should keep the copy simple:

- Body pattern: `<Fallback Account> is available again`

`Account Available` is for a fallback becoming useful again. It must not fire
when the first saved account appears, when the only saved account is available,
or when the available account is already the active local or verified remote
account.

## Actions

Notification actions should offer direct use targets when the platform supports it:

- `Use on This Mac`
- `Use on <remote host>`

If multiple direct actions do not fit cleanly, fall back to a single best-option action.

## Dedupe

After CodexPill notifies for a saved account, that account is suppressed until CodexPill observes it become active locally or on a verified remote host.

## Acceptance Criteria

- If macOS notification permission is denied, notification modes render
  unavailable and route to System Settings without deleting saved preferences.
- `Account Available` fires only for inactive fallback accounts becoming useful
  again.
- `Current Runs Out` copy explains the active target and direct actions route
  through stale-checked local or remote switch flows.
- A delivered account notification is suppressed until CodexPill observes that
  account become active locally or on a verified remote host.

## Validation Scenario Candidates

- `notifications-permission-denied-menu-state`
- `notifications-account-available-policy`
- `notifications-current-runs-out-action`
- `notifications-dedupe-after-delivery`

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Denied macOS permission disables notification modes and routes to System Settings without deleting preferences. | `unit` plus `deterministic-ui` | `make verify-notifications-permission-denied-menu-state-scenario` running `MenuBarMenuBuilderTests` and `MenuBarRuntimeValidationTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/notifications-permission-denied-menu-state/workflow-receipt.json`, and `scenario-summary.json`. | Denied permission renders mode rows unchecked/disabled, shows `Enable in macOS Settings…`, opens System Settings through a fake launcher when selected, preserves saved CodexPill notification preferences, and does not request authorization again. | Synthetic permission/preferences only; no private system identifiers, account data, auth payloads, tokens, paths, emails, or hostnames. |
| `Account Available` fires only for inactive fallback accounts becoming useful again. | `unit` | `make verify-notifications-account-available-policy-scenario` running `InactiveAccountAvailabilityRankingTests` and `MenuBarNotificationWorkflowTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/notifications-account-available-policy/workflow-receipt.json`, and `scenario-summary.json`. | First-saved, only-saved, already-active, barely usable, and non-fallback accounts do not trigger; inactive fallback accounts becoming useful do trigger once with simple copy and no direct actions; the notified account is suppressed until activation resets dedupe state. | Synthetic account/rate-limit fixtures only; no raw auth, account identifiers, emails, hostnames, paths, or tokens. |
| `Current Runs Out` copy explains the target and actions route through stale-checked switch flows. | `workflow-event-log` | `make verify-notifications-current-runs-out-action-scenario` running notification policy, payload rendering, workflow response, and runtime validation tests. | `build/results/local/CodexPill.xcresult`, `build/verification/notifications-current-runs-out-action/workflow-receipt.json`, and `scenario-summary.json`. | Local and remote active-account exhaustion can trigger `Current Runs Out`; rendered copy names the exhausted target and fallback; direct actions expose local and remote switch targets; action handling re-checks current state, substitutes safer current targets with explanatory copy, drops stale remote requests, and surfaces switch failures through the app. | Synthetic notification/account/remote-host fixtures only; no real account identifiers, emails, hostnames, auth payloads, tokens, private paths, or raw app-server data. |
| Delivered account notification is suppressed until that account becomes active. | `unit` | `make verify-notifications-dedupe-after-delivery-scenario` running notification state, workflow delivery, settings persistence, and runtime activation tests. | `build/results/local/CodexPill.xcresult`, `build/verification/notifications-dedupe-after-delivery/workflow-receipt.json`, and `scenario-summary.json`. | Delivered notifications record reason and window state, disarm repeated delivery across later windows, and re-arm only after CodexPill observes the account become active locally or on a verified remote host. | Synthetic account/window/remote-host fixtures only; no raw auth, tokens, emails, hostnames, private paths, or app-server payloads. |

## Validation Targets

- Unit tests for permission-to-menu-state mapping.
- Unit policy tests for `Account Available` trigger conditions.
- Workflow-event tests for `Current Runs Out` action routing and stale checks.
- Unit tests for notification dedupe reset after active-account observation.
- Privacy review confirming notification artifacts avoid raw auth, account
  identifiers, emails, hostnames, paths, tokens, and app-server payloads.
