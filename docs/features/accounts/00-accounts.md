# Accounts

CodexPill accounts are locally saved Codex authentication snapshots with user-facing metadata. Account features must preserve a clear distinction between catalog management and switching the active Codex account.

Feature documents define what the account workflow must do. UX sections define how the user experiences those workflows in menus, alerts, and panels.

## Current User-Facing Features

### 01. Add Account

Add another Codex account to CodexPill's local catalog without changing the currently active local Codex account.

See [Add Account](01-add-account.md).

### 02. Switch Account

Activate a saved account on This Mac or on a configured remote host through the explicit switch actions.

See [Switch Account](02-switch-account.md).

### 03. Remove Account

Remove a saved account snapshot from CodexPill's local catalog.

See [Remove Account](03-remove-account.md).

### 04. Rename Account

Rename the CodexPill display label for a saved account without changing the underlying Codex identity or auth snapshot.

See [Rename Account](04-rename-account.md).

### 05. Refresh Accounts

Refresh account metadata, plan, and rate-limit snapshots for the full account surface: current local account, saved catalog accounts, and configured remote accounts.

See [Refresh Accounts](05-refresh-accounts.md).

## Related Account Operations

### Remote Account Setup

Remote host setup installs and switches saved account snapshots on configured remote hosts. It is related to account switching, but host management has its own feature surface.

## UX Ownership

The whole menubar layout, including section ordering and the lower App Controls section, is owned by [Menubar](../menubar.md). Accounts owns the account-specific content inside those sections.

## Active Account UX

Active account presentation answers: "Which account am I using right now, and where?"

CodexPill shows active accounts in one unified top section:

- `Active Account`: one active account card.
- `Active Accounts`: multiple active account cards.

### Local Active Account

The local current account appears first when CodexPill can match the live local Codex auth state to a saved account.

The card should show:

- Display name.
- Plan as a compact pill.
- Location or freshness metadata, such as `This Mac`, `workstation`, `This Mac + workstation`, or `Updated 1min ago`.
- Session usage and reset timing when Codex returns a shorter session-like quota window.
- Weekly usage and reset timing when Codex returns a weekly quota window.
- A neutral expected-pace marker inside each usage bar when reset-window duration is available and `Preferences > Usage Bars > Show Pace Markers` is enabled. This marker is visual only; it must not add pacing text to the card.

If CodexPill cannot match the live local Codex auth to a saved account, it should show a clear unmatched or empty state instead of displaying stale saved-account data as current.

### Remote Active Account Cards

Remote active account cards appear in the same top section for connected verified remote hosts.

The card should show:

- Saved account display name.
- Remote host name or destination.
- Plan as a compact pill.
- Session and weekly usage values from the remote target, classified by returned quota-window duration.
- The same neutral expected-pace marker as the local current account when reset-window duration is available and `Preferences > Usage Bars > Show Pace Markers` is enabled.

Remote cards must prefer remote target values over local catalog values when the remote active account is verified. The user should not see the local catalog's stale limits as if they represented the remote host.

### Duplicate Local And Remote Accounts

If the same saved account is active locally and on a connected verified remote host, CodexPill renders one active account card and shows compact location context in the metadata line, such as `This Mac + workstation`. The card continues to show local current-account limits; remote host management and troubleshooting remain under `Hosts`.

If only the local account is active, the metadata line shows freshness, such as `Updated 1min ago`. If local and remote accounts are different and therefore render as separate cards, the local card shows `This Mac` and each remote card shows its host context.

If the same saved account is active on multiple connected verified remote hosts and not active locally, CodexPill renders one active account card with the host names joined in the metadata line, such as `workstation + linux-box`.

The user must be able to answer:

- Is this account active on This Mac?
- Is this account active on a remote host?
- Where do I inspect or manage the remote host if it needs attention?

### Error And Pending States

Remote pending, failed, disconnected, or unverified states should not be presented as verified current-account facts.

When the app cannot verify a remote account, it should either hide the remote account card or show an explicit recovery state owned by the Remote Hosts feature.

## Account Menu And Catalog UX

CodexPill adapts the saved-account menu to the account and host setup:

- With one saved account and no configured host, CodexPill hides the saved-account list and shows `Account > Add Account…, Rename…, Remove…`.
- With multiple saved accounts and no configured host, CodexPill shows `Other Accounts` rows excluding the active local account. The active local account is managed through `Account > Add Account…, Rename…, Remove…` so account actions stay grouped.
- With configured hosts, CodexPill keeps the visible saved-account row design because each row can expose local and remote target actions.

The catalog is not the same as active-account presentation. It shows saved options, while `Active Account(s)` shows active targets. Management actions for the active local account should not force an otherwise duplicate row to appear in the saved-account list.

### Row Content

Each visible row should show:

- Saved account display name.
- Compact session usage summary.
- Compact weekly usage summary.
- A submenu affordance.

Rows should stay compact. Detailed target actions belong in the account submenu.

### Row Data Source

Catalog rows primarily use saved catalog metadata and latest known rate-limit snapshots.

If an account is currently active on a remote host and that remote value is fresher or target-specific, the row may prefer that remote target's values, as long as the UI remains clear about where those values came from.

### Ordering

Rows are ordered by the app's shared account availability ranking.

This means the catalog should help the user find the most useful account first, not simply list accounts alphabetically.

### Overflow

When the visible account limit hides saved accounts, the menubar shows `More Accounts…`. The default visible saved-account count is five.

The overflow menu remains part of the same saved account catalog and should use the same row and submenu behavior.

### Empty State

When no saved accounts exist, the menu should guide the user toward `Add Account…`.

The empty state should not imply that CodexPill can switch accounts before at least one account is saved.

## Account Submenu UX

The account submenu is the per-account action surface. It should identify the account, show where it is currently used, and expose actions without forcing the user to open separate detail screens.

### Current Shape

The submenu currently contains:

- A disabled email identity row such as `name@example.com` or `No email`.
- A disabled usage row such as `In use on: This Mac`.
- Switch actions for available targets, such as `Switch on This Mac` and `Switch on workstation`.
- Management actions: `Rename…` and `Remove…`.

### Identity

The submenu should show the account email address near the top when available. This helps distinguish accounts with similar display names.

Recommended order:

1. Email address as disabled informational text.
2. Usage row, for example `In use on: This Mac`.
3. Switch actions.
4. Rename and remove actions.

If the email is unknown, show `No email` in the same disabled informational row.

### Actions

Switch on This Mac:

- Uses the normal local switch path.
- Presents the local switch confirmation unless the caller is an explicit no-second-confirmation path such as Add Account success.

Switch on remote host:

- Uses the normal remote switch/install flow for that host.
- Must verify or surface remote errors instead of silently assuming success.

Rename:

- Uses a native text-input alert.
- Makes clear that the label changes only inside CodexPill.

Remove:

- Uses a destructive confirmation alert.
- If the removed account is active locally or on a connected remote host, CodexPill signs out those active targets before deleting the saved snapshot.
- If any required sign-out fails, CodexPill keeps the saved account so the user does not lose the main control surface for an active login.

### Visual Contract

Submenu rows should remain compact because this is a menu, not a details panel. Extra explanatory copy belongs in confirmation alerts or feature docs, not in the menu.

## Acceptance Criteria

- When no saved accounts exist, the menu guides the user toward `Add Account…`
  and does not imply switching is possible.
- When saved accounts exceed the visible-account limit, hidden accounts remain
  discoverable under `More Accounts…` and keep the same submenu behavior as
  visible rows.
- If live local auth does not match a saved account, CodexPill does not present
  any saved account as active.
- Remote active account cards prefer verified remote target values over stale
  local catalog values.

## Validation Scenario Candidates

- `menu-empty-catalog`
- `menu-account-overflow`
- `menu-unmatched-active-account`
- `remote-host-rate-limit-fallback`

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Empty catalog guides toward `Add Account…` and does not imply switching. | `ui-structure-contract` | `make verify-ui SCENARIO=menu-empty-catalog`, updated to emit Kite's `kite.ui-structure-contract.v1` artifact. | Required: `build/verification/menu-empty-catalog/ui-structure-contract.json` and `scenario-summary.json`. Optional/debug: hosted screenshot under `screenshots/`. | The Kite UI structure artifact proves the hosted menu has `Active Account`, `Manage Accounts`, and `Preferences` in order; shows the current empty active-account row and enabled `Add Account…` action; omits saved-account rows, `More Accounts…`, and switch actions; and records live/menu/pixel non-claims. | Synthetic empty catalog only; artifacts must not include raw auth, tokens, account identifiers, private paths, emails, hostnames, prompts, or raw AppKit payloads. |
| Account overflow keeps hidden accounts discoverable. | `ui-structure-contract` | `make verify-ui SCENARIO=menu-account-overflow` | Required: `build/verification/menu-account-overflow/ui-structure-contract.json` and `scenario-summary.json`. Optional/debug: hosted screenshot and UI tree. | The Kite UI structure artifact proves visible saved-account rows, the `More Accounts…` overflow section, and saved-account structure remain present without claiming pixel fidelity or native pointer interaction. | Synthetic saved accounts only; no raw auth payloads, tokens, private paths, real emails, real hostnames, or stable account identifiers. |
| Unmatched local auth does not present a saved account as active. | `ui-structure-contract` | `make verify-ui SCENARIO=menu-unmatched-active-account` | Required: `build/verification/menu-unmatched-active-account/ui-structure-contract.json` and `scenario-summary.json`. Optional/debug: hosted screenshot and UI tree. | The Kite UI structure artifact proves the active section shows `No active saved account` while saved accounts remain catalog rows and no live auth/account-switching claim is made. | Synthetic unmatched auth state only; artifacts must not include raw auth payloads, tokens, account identifiers, private paths, emails, hostnames, or prompts. |
| Remote active cards prefer verified remote values over stale local catalog values. | `contract-fixture` plus `unit` | `make verify-remote-host-rate-limit-fallback-scenario` running remote rate-limit resolution, account catalog projection, menu state, and runtime validation suites. | `build/results/local/CodexPill.xcresult`, `build/verification/remote-host-rate-limit-fallback/contract-receipt.json`, and `scenario-summary.json`. | Verified remote values win for the remote card when meaningful; fallback values appear only when remote data is missing, partial, zeroed, expired, or suspicious and are not presented as live SSH proof. | Synthetic host/account/rate-limit fixtures only; no raw SSH output, auth payloads, tokens, private paths, real emails, or hostnames. |

### Menu Empty Catalog UI Structure Contract

This is the target contract for the Slice 5 Kite migration. It updates proof
ownership only; it does not change user-facing copy, menu order, or Add Account
behavior.

Product-owned inputs:

- Scenario id: `menu-empty-catalog`.
- Feature id: `account-catalog-empty-state`.
- Acceptance criterion id: `empty-catalog-guides-to-add-account`.
- Fixture state: no active account, no inactive accounts, no remote hosts, idle
  menu state, synthetic preferences.
- Product command: `make verify-ui SCENARIO=menu-empty-catalog`.

Kite-owned proof shape:

- Artifact kind: `ui_structure_contract`.
- Schema version: `kite.ui-structure-contract.v1`.
- Required artifact path:
  `build/verification/menu-empty-catalog/ui-structure-contract.json`.
- Required summary path:
  `build/verification/menu-empty-catalog/scenario-summary.json`.
- Optional debug artifact:
  `build/verification/menu-empty-catalog/screenshots/menu-empty-catalog.png`.

Required structure assertions:

- `node-exists`: top-level `Active Account` section is visible.
- `node-exists`: empty active-account row is visible using current product copy.
- `node-exists`: `Add Account…` menu item is visible and enabled.
- `action-available`: `Add Account…` exposes the add-account action.
- `node-absent`: no saved-account catalog row is present.
- `node-absent`: `More Accounts…` is absent.
- `action-absent`: local or remote switch actions are absent.
- `child-order`: top-level sections appear as `Active Account`,
  `Manage Accounts`, then `Preferences`.

Required non-claims:

- Does not prove pixel rendering, typography, spacing, or screenshot visual
  fidelity.
- Does not prove native menu opening, native click routing, focus, or
  hittability.
- Does not prove Add Account sign-in workflow behavior.
- Does not prove live Codex auth lookup, account switching, or live macOS menu
  bar behavior.

Implementation notes:

- CodexPill should keep only a thin exporter that maps product menu state and
  AppKit menu metadata into Kite's generic structure artifact.
- Existing hosted screenshots may remain useful for debugging, but they must not
  be required evidence for this scenario unless a later scenario explicitly
  claims visual rendering.
- Existing `MenuBarValidationSnapshot` assertions can be reused as product
  exporter tests, but generic assertion semantics belong to Kite.
- Changing the empty-state copy is out of scope for this migration. If the copy
  should become more explicit than the current product text, refine that as a
  product UX slice.

## Validation Targets

- Kite UI structure contract proof for `menu-empty-catalog`.
- Hosted menu projection proof for overflow and unmatched active account states
  until those scenarios are migrated.
- Unit or contract-fixture proof for remote rate-limit value selection.
- Privacy review confirming account-menu artifacts use synthetic accounts,
  hosts, and rate-limit values.
