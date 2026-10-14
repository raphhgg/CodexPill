# Menubar

The menubar feature owns the menu's composition: which sections appear, in what order, and what each card and side menu offers. The behavior behind each item belongs to its own feature doc.

## Main Menu

Top to bottom, nothing else:

1. One card per visible tool: `Claude`, `Codex`, `Cursor` by default. Separators sit between cards.
2. The app's own items:

   ```text
   ─────
   Add Account ›        Codex…
   ─────
   Appearance ›
   Refresh Every ›      1 minute … 30 minutes
   Hide Emails
   Launch at Login
   ─────
   Diagnostics…
   About
   ```

3. The status message, only while an account operation runs.
4. `Quit ⌘Q`

There is no `Settings` submenu. A tool with nothing set up has no card. Codex has a card once one account is saved. Claude and Cursor have one once connected ([Claude Usage](claude-usage.md), [Cursor Usage](cursor-usage.md)). `Appearance › Show Tools` hides a card.

With no card at all, on a first run or with every tool hidden, the menu starts at `Add Account ›`. It is the same list, so a new user sees where to begin first.

The user orders the cards from each side menu. The first card drives the menu bar icon ([Status Bar](status-bar.md)).

## Card

Every tool uses the same card. It is one hover cell with a side menu and no chevron.

- **Header.** The tool's monochrome mark, its name, and the plan tag on the right: `Pro x20` or `Pro x5` for Codex, `Max x20` or `Max x5` for Claude, `Pro` for Cursor. The marks come from Lobe Icons (MIT, see `THIRD_PARTY_NOTICES.md`).
- **Meters.** One per window the tool reports, shortest first, named by its length: `Session` (5 hours), `Weekly` (7 days), `Monthly` (28 to 31 days), or `Billing cycle` for Cursor. Any other length is titled by that length, such as `8 days`. Claude's per-model weekly limits follow `Weekly`, one meter each, titled `<model> this week`, such as `Fable this week`. The Claude side menu's `Show Fable Limits` hides them. A Codex Free account shows only `Monthly`. A window the tool does not report has no meter. Codex Pro and Pro Lite hide the session window. Each meter shows the bar with an even-pace tick placed by the window's real length, `11% used` on the left and `Resets in 2h53` in grey on the right. A reset more than a week away, and any billing cycle's, reads as a date: `Resets 30 Oct`. Meters follow the `Usage Bars` settings.
- **Credits.** One line before the reset row when the tool reports credits or paid usage: `62,498 credits` or `Unlimited credits` for Codex, `$12.40 of $50.00 extra usage` (or `$12.40 extra usage` with no cap) for Claude extra usage and Cursor on-demand. A balance shows whole credits, rounded down. Nothing reported means no line, never `0`. Credits never change a meter or the account ranking.
- **Codex resets.** `2 resets available` with `Next expires 5 Nov` on the right, or `Expires 5 Nov` for one credit ([Codex Reset Credits](codex-reset-credits.md)). Claude has no reset row.
- **Cursor.** An unlimited plan has no meter.
- **States.** A title and at most one short line replace or precede the meters:

  | State | Title | Line |
  |---|---|---|
  | Waiting for the first read, from the moment a tool is connected | `Waiting for Codex usage` (or the tool's name) | none |
  | Stale | none, meters dimmed | `As of 10:26` |
  | Read failed with an earlier reading | the failure title, meters dimmed | `As of 10:26` |
  | Read failed with no earlier reading | the failure title | the failure line |
  | No Codex account in use | `No saved account in use` | `Pick one in this menu.` |

  Failure titles come from `ProviderCopy`, for example `Can't reach Anthropic` / `Retrying in a few minutes.`, `Cursor is busy`, `Cursor isn't installed`, `Allow Keychain access`. A Codex reading older than two refreshes, and at least 15 minutes, is stale.
- **Action rows.** While a state lasts, one row sits under the card: `Allow Keychain Access…`.

## Side Menu

Hovering a card opens its side menu:

1. The email of the account in use, checked and disabled. For Claude and Cursor it is the account their own app is signed in to, from the last reading.
2. Codex only: one row per other saved account, by email. Each row opens `Use` and `Remove…`. `Remove…` asks first. Removing a Codex account also signs this Mac out when `auth.json` still uses it.
   An account without an email reads as its workspace, then its plan (`Plus account`), else `Saved account`. Repeated labels get a number in saved order: `Saved account 2`. Alerts name an account with the same label.
   Each one carries that account's last limits on a second, smaller line, in the user's % used or % left: `Session 12% · Weekly 40% used`, `Weekly 17% used` for Codex Pro, or `Monthly 3% used` for Codex Free. A reading older than 30 minutes adds `· as of 10:26`.
3. Codex only: `Use a Reset…`, then one disabled `Expires <date>` line per credit Codex listed, and `Token Usage ›` when token usage is on ([Token Usage](token-usage.md)).
4. `Move to Top`, `Move Up`, `Move Down`, when there is more than one card. Moves that do not apply are disabled.
5. Claude only: `Show Fable Limits`, named after the models with their own limit in the current reading (`Show Fable and Opus Limits` for two). Hidden when the reading has none. See [Claude Usage](claude-usage.md).
6. Codex only: `Add Codex Account…`.

Claude and Cursor have no other account rows: Refill reads only the account their own app is signed in to. A Claude or Cursor side menu with one card and no model limit holds only the email. The Codex account in use has no remove item. `Appearance › Show Tools` hides a tool.

`Hide Emails` masks every email the menu, its alerts and the tooltip show: `alex.side@example.com` reads `al•••e@example.com`. The domain stays visible.

Every tool item carries a `ProviderMenuAction` and goes through `MenuBarCoordinator.performProviderAction(_:)`.

## App Items

`Add Account ›` offers only `Codex…`. Adding a Codex account shows the Codex card again if it was hidden. Claude and Cursor have no accounts to add: `Show Tools` connects them.

```text
Appearance ›   Show Tools ›  Menu Bar Label ›  Icon Style ›  Usage Bars ›  App Icon ›  ─  Show Token Usage
```

`Show Tools` has one checkmark item each for `Claude`, `Codex` and `Cursor`, checked while that tool's card shows.

- Unchecking `Claude` or `Cursor` disconnects it: the card goes and nothing is read, with no alert. Checking it connects, through its consent alert.
- Unchecking `Codex` hides its card and stops the Codex reads. Saved accounts and `auth.json` stay as they are. Checking it shows the card and reads it again. With no saved Codex account, checking it adds one. The choice is saved as `hidesCodex` in user defaults.
- Every tool can be hidden. The menu bar icon then shows the app's own glyph, and the menu is the first-run one.

`Theme` picks the app icon, the usage bar colors and the Token Usage colors. [Theme](app-controls/02-theme.md) owns it.

`Diagnostics…` first explains what the export contains, then writes a redacted JSON file only if the user confirms. The report holds allowlisted fields, per-export account aliases, every limit window each account reported (its kind, its menu title and a used-share category: available, limited or exhausted), summarized freshness states and recent Refill workflow events. It never includes raw logs, auth JSON, snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, stable account IDs, prompt or session content, or raw stderr.

## Rendering

The menu is a native `NSMenu`. Each card is an `NSMenuItem` whose view is a `MenuCardItemView` hosting the SwiftUI `ToolCardView`, with the side menu as its submenu. `MenuCardItemView` draws the hover highlight, because AppKit draws none for view-based items. Views do no I/O: `MenuBarMenuState.toolSections` turns the state into one `ToolSection` per card.

## Validation Notes

`ToolSectionTests` cover the card model per state: order, hidden windows, titles and lines, plan tags, masked emails and moves. `MenuBarMenuBuilderTests` build the `NSMenu` and assert item titles, order, submenus and the action each item sends. Coordinator flows live in `MenuBarCoordinatorTests`.
