# Menubar

The menubar feature owns the overall `MenuBarExtra` popup composition.

It does not own every behavior behind each row. Instead, it defines where feature entry points appear, how sections are ordered, and how menu-level states such as busy/status/quit are presented.

## Purpose

The menubar popup is CodexPill's primary product surface. It combines account status, remote status, saved account actions, and app-level controls in one native menu.

## Section Order

The menu is ordered as:

1. `Active Account` or `Active Accounts`
2. `Accounts`, when saved catalog entries are visible
3. `More Accounts…`, when saved catalog entries overflow the visible limit
4. App Controls
5. Status message, when needed
6. `Quit`

## Active Account Section

Owned behavior: [Accounts](accounts/00-accounts.md).

UX responsibility here:

- Use `Active Account` for one active account card and `Active Accounts` for multiple active account cards.
- Present the active local saved account and connected verified remote active accounts in one unified section.
- Collapse the local and remote surfaces into one card when the same saved account is active on This Mac and a connected verified remote host.
- Show enough plan, location, and session/weekly usage information to answer "what am I using right now and where?"
- If no saved account matches any live active account, show a clear empty state instead of pretending an account is active.

## Accounts Section

Owned behavior: [Accounts](accounts/00-accounts.md).

UX responsibility here:

- Show saved catalog rows below current/remote cards.
- Keep rows compact: account display name plus session/weekly summary.
- Use a submenu per row for target switching and account management.
- Use `More Accounts…` when the visible-account limit hides additional saved accounts.

## App Controls Section

The lower section is called App Controls in product docs. It is not called Preferences because it contains both settings and feature entry points.

Entries:

- `Add Account…`: entry point owned by [Accounts](accounts/00-accounts.md).
- `Hosts`: entry point owned by [Remote Hosts](remote-hosts.md).
- `Notifications`: entry point owned by [Notifications](notifications.md).
- `Refresh Interval`: setting that controls scheduled refresh cadence.
- `Preferences`: visual settings owned by [Status Bar](status-bar.md), plus app-level controls such as [Launch at Login](app-controls/01-launch-at-login.md).
- `Diagnostics…`: user-initiated support artifact export. CodexPill first explains what the export contains, then writes a redacted JSON file only if the user confirms. The report is built from allowlisted diagnostic fields, per-export account/host aliases, summarized freshness/result states, and recent CodexPill-owned workflow events. It must not include raw logs, auth JSON, saved snapshots, raw UserDefaults, raw SSH output, emails, hostnames, local paths, tokens, stable account IDs, prompt/session content, or raw stderr.
- `About`: app-level informational alert.
- `Quit`: app-level quit command, separated from status and controls.

## Busy And Status States

When CodexPill is busy, menu actions that would conflict with the active workflow should be disabled or routed through their existing confirmation flow.

If `statusMessage` is visible, it appears below App Controls and above `Quit`.

## Acceptance Criteria

- The hosted default menu keeps the documented section order and does not claim
  live auth, live Codex state, preview rendering, or native menu-bar behavior.
- Busy workflows expose a menu status message and disable or route conflicting
  menu actions through their existing confirmation paths.
- Diagnostics export requires explicit user confirmation before writing any
  support artifact.
- Diagnostics export writes only allowlisted, redacted support data.

## Validation Scenario Candidates

- `hosted-menu-default`
- `menu-busy-status`
- `diagnostics-export-confirmation`

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| The hosted default menu keeps the documented section order and does not claim live state. | `deterministic-ui` | `make verify-ui SCENARIO=hosted-menu-default` | `build/verification/hosted-menu-default/screenshots/hosted-menu-default.png`, `ui-tree.json`, and `scenario-summary.json`. | The hosted menu projection shows the expected sections and metadata for synthetic saved-account state, while the scenario summary records non-claims for SwiftUI preview rendering, live macOS menu-bar behavior, and live Codex state. | Synthetic accounts/hosts only; artifacts must not include raw auth payloads, tokens, account identifiers, private paths, prompts, emails, or hostnames outside synthetic fixture values. |
| Busy workflows expose status and disable or route conflicting actions. | `deterministic-ui`; future `workflow-event-log` for routed confirmation flows. | `make verify-ui SCENARIO=menu-busy-status`; future fake workflow/action recorder for confirmation routing. | `build/verification/menu-busy-status/screenshots/menu-busy-status.png`, `ui-tree.json`, and `scenario-summary.json`; future structured action-availability receipt. | The hosted menu projection shows `Refreshing account data...` before `Quit` and marks `Add Account…` disabled. This deterministic scenario does not prove workflow action dispatch, confirmation routing, or event-log ordering. | Synthetic accounts only; artifacts and future receipts must not include raw auth payloads, tokens, account identifiers, private paths, emails, or hostnames. |
| Diagnostics export requires confirmation and writes only a redacted support artifact. | `diagnostics-export` | Future diagnostics export fixture with cancel and confirm branches. | Redacted diagnostics JSON plus negative leakage assertions. | Cancel writes no report; confirm writes only allowlisted aliases, freshness/result summaries, and CodexPill-owned workflow events. | The report must fail validation if it contains raw logs, auth JSON, saved snapshots, raw UserDefaults, raw SSH output, emails, hostnames, local paths, tokens, stable account IDs, prompt/session content, or raw stderr. |

## Validation Notes

Menu UI validation should assert section ordering, direct-row versus submenu placement, action wiring, disabled states during busy work, and the presence or absence of optional sections.
