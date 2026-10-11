# Menubar

The menubar feature owns the menu's composition: which sections appear, in what order, and what each card and side menu offers. The behavior behind each item belongs to its own feature doc.

## Main Menu

Top to bottom, nothing else:

1. One card per tool that has a saved account or a connection: `Claude`, `Codex`, `Cursor` by default. Separators sit between cards.
2. `Settings ›`
3. The status message, only while an account operation runs.
4. `Quit ⌘Q`

A tool with nothing set up has no card. Codex has a card once one account is saved. Claude and Cursor have one once connected ([Claude Usage](claude-usage.md), [Cursor Usage](cursor-usage.md)).

With nothing set up at all, the menu is `Add Account ›` (Codex…, Claude…, Cursor…), `Settings ›` and `Quit`.

The user orders the cards from each side menu. The first card drives the menu bar icon ([Status Bar](status-bar.md)).

## Card

Every tool uses the same card. It is one hover cell with a side menu and no chevron.

- **Header.** The tool's monochrome mark, its name, and the plan tag on the right: `Pro x20` or `Pro x5` for Codex, `Max x20` or `Max x5` for Claude, `Pro` for Cursor. The marks come from Lobe Icons (MIT, see `THIRD_PARTY_NOTICES.md`).
- **Meters.** One per window the tool reports: `Session`, `Weekly`, or `Billing cycle`. A window the tool does not report has no meter. Codex Pro and Pro Lite hide the session window. Each meter shows the bar with an even-pace tick, `11% used` on the left and `Resets in 2h53` (or `Resets 30 Oct` for a billing cycle) in grey on the right. Meters follow the `Usage Bars` settings.
- **Codex resets.** `2 resets available` with `Next expires 5 Nov` on the right, or `Expires 5 Nov` for one credit ([Codex Reset Credits](codex-reset-credits.md)). Claude has no reset row.
- **Cursor spend.** `On-demand: $12.34 of $50.00` under the meter. An unlimited plan has no meter.
- **States.** A title and at most one short line replace or precede the meters:

  | State | Title | Line |
  |---|---|---|
  | Waiting for the first read, from the moment a tool is connected | `Waiting for Codex usage` (or the tool's name) | none |
  | Stale | none, meters dimmed | `As of 10:26` |
  | Read failed with an earlier reading | the failure title, meters dimmed | `As of 10:26` |
  | Read failed with no earlier reading | the failure title | the failure line |
  | No Codex account in use | `No saved account in use` | `Pick one in this menu.` |
  | Signing in, after `Add Claude Account…` or `Sign In…` | `Finish signing in in your browser` | none |

  Failure titles come from `ProviderCopy`, for example `Can't reach Anthropic` / `Retrying in a few minutes.`, `Cursor is busy`, `Cursor isn't installed`, `Allow Keychain access`. A Codex reading older than two refreshes, and at least 15 minutes, is stale.
- **Action rows.** While a state lasts, one row sits under the card: `Allow Keychain access…`, `Cancel Sign-In`, or `Sign In…` when Claude Code has no readable sign-in (it runs `Add Claude Account…`).

## Side Menu

Hovering a card opens its side menu:

1. The email of the account in use, checked and disabled.
2. `Use <email>` when exactly one other account is saved, or `Use Another <Tool> Account ›` listing them.
   An account without an email reads as its organization, else `Saved account`. Repeated labels get a number in saved order: `Saved account 2`.
   Each one carries that account's last limits on a second, smaller line, in the user's % used or % left: `Session 12% · Weekly 40% used`, or `Weekly 17% used` for Codex Pro. A reading older than 30 minutes adds `· as of 10:26`. Codex and Claude read inactive accounts every 15 minutes; Cursor accounts have no line yet.
3. Codex only: `Use a Reset…`, then one disabled `Expires <date>` line per credit Codex listed, and `Token Usage ›` when token usage is on ([Token Usage](token-usage.md)).
4. `Move to Top`, `Move Up`, `Move Down`, when there is more than one card. Moves that do not apply are disabled.
5. `Add <Tool> Account…` and `Remove <Tool> Account ›` listing every saved account.
   `Add Codex Account…` and `Add Claude Account…` run the tool's own sign-in without touching the account in use; `Add Cursor Account…` saves the sign-in Cursor uses now. Claude also has `Save Current Sign-In`. Without the `claude` command, `Add Claude Account…` is disabled with `Install Claude Code first` under it.
6. Claude and Cursor only: `Disconnect <Tool>`, last.

`Hide Emails` masks every email the menu and the tooltip show: `alex.side@example.com` reads `al•••e@example.com`. The domain stays visible.

Every tool item carries a `ProviderMenuAction` and goes through `MenuBarCoordinator.performProviderAction(_:)`.

## Settings

```text
Add Account ›        Codex…  Claude…  Cursor…
─────
Appearance ›         Menu Bar Label ›  Icon Style ›  Usage Bars ›  ─  Show Token Usage
Hide Emails
Refresh Every ›      1 minute … 30 minutes
Launch at Login
─────
Diagnostics…
About
```

`Claude…` and `Cursor…` connect a tool that is not connected yet. Otherwise `Claude…` runs `Add Claude Account…` and `Cursor…` saves the sign-in Cursor uses now as another account.

`Diagnostics…` first explains what the export contains, then writes a redacted JSON file only if the user confirms. The report holds allowlisted fields, per-export account aliases, summarized freshness states and recent CodexPill workflow events. It never includes raw logs, auth JSON, snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, stable account IDs, prompt or session content, or raw stderr.

## Rendering

The menu is a native `NSMenu`. Each card is an `NSMenuItem` whose view is a `MenuCardItemView` hosting the SwiftUI `ToolCardView`, with the side menu as its submenu. `MenuCardItemView` draws the hover highlight, because AppKit draws none for view-based items. Views do no I/O: `MenuBarMenuState.toolSections` turns the state into one `ToolSection` per card.

## Validation Notes

`ToolSectionTests` cover the card model per state: order, hidden windows, titles and lines, plan tags, masked emails and moves. `MenuBarMenuBuilderTests` build the `NSMenu` and assert item titles, order, submenus and the action each item sends. Coordinator flows live in `MenuBarCoordinatorTests`.
