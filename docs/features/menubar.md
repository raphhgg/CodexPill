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
- **Meters.** One per window the tool reports, shortest first, named by its length: `Session` (5 hours), `Weekly` (7 days), `Monthly` (28 to 31 days), or `Billing cycle` for Cursor. Any other length is titled by that length, such as `8 days`. Claude's per-model weekly limits follow `Weekly`, one meter each, titled `<model> this week`, such as `Fable this week`. `Show Model Limits` hides them. A Codex Free account shows only `Monthly`. A window the tool does not report has no meter. Codex Pro and Pro Lite hide the session window. Each meter shows the bar with an even-pace tick placed by the window's real length, `11% used` on the left and `Resets in 2h53` in grey on the right. A reset more than a week away, and any billing cycle's, reads as a date: `Resets 30 Oct`. Meters follow the `Usage Bars` settings.
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
- **Action rows.** While a state lasts, one row sits under the card: `Allow Keychain access…`, `Cancel Sign-In`, or `Sign In…` when Claude Code has no readable sign-in (it runs `Add Claude Account…`). A signed-out Cursor card has no `Sign In…`, because adding a Cursor account leaves Cursor itself signed out.
- **Signing in.** While a tool's own sign-in runs, the card reads `Finish signing in in your browser` for Claude or `Sign in in the new Cursor window` for Cursor, with `Cancel Sign-In` under it.

## Side Menu

Hovering a card opens its side menu:

1. The email of the account in use, checked and disabled.
2. One row per other saved account, by email. Each row opens `Use` and `Remove…`. `Remove…` asks first. Removing a Codex account also signs this Mac out when `auth.json` still uses it.
   An account without an email reads as its organization, a Codex account then as its plan (`Plus account`), else `Saved account`. Repeated labels get a number in saved order: `Saved account 2`. Alerts name an account with the same label.
   Each one carries that account's last limits on a second, smaller line, in the user's % used or % left: `Session 12% · Weekly 40% used`, `Session 12% · Weekly 40% · Fable this week 8% used` for Claude with a model limit (none while `Show Model Limits` is off), `Weekly 17% used` for Codex Pro, or `Monthly 3% used` for Codex Free. Cursor's line is its billing cycle: `40% used`. A reading older than 30 minutes adds `· as of 10:26`. Every tool reads inactive accounts every 15 minutes. A Cursor account whose saved token expired keeps its last line, with its time.
3. Codex only: `Use a Reset…`, then one disabled `Expires <date>` line per credit Codex listed, and `Token Usage ›` when token usage is on ([Token Usage](token-usage.md)).
4. `Move to Top`, `Move Up`, `Move Down`, when there is more than one card. Moves that do not apply are disabled.
5. `Add <Tool> Account…`.
   `Add <Tool> Account…` runs the tool's own sign-in without touching the account in use. Cursor's opens a second Cursor window with a throwaway profile. The account Claude Code or Cursor is signed in to is saved automatically once that tool is connected. Without the `claude` command or Cursor, the add item is disabled with `Install Claude Code first` or `Install Cursor first` under it.
   A switch while that tool's sign-in runs is refused: `Finish signing in first` / `Or cancel the sign-in.`

The account in use has no remove item. Claude and Cursor save the live account automatically, so a removed one would come straight back. `Disconnect <Tool>` lives in Settings.

`Hide Emails` masks every email the menu, its alerts and the tooltip show: `alex.side@example.com` reads `al•••e@example.com`. The domain stays visible.

Every tool item carries a `ProviderMenuAction` and goes through `MenuBarCoordinator.performProviderAction(_:)`.

## Settings

```text
Add Account ›        Codex…  Claude…  Cursor…
Disconnect Claude    (one per connected tool: Claude, Cursor)
─────
Appearance ›         Menu Bar Label ›  Icon Style ›  Usage Bars ›  App Icon ›  ─  Show Token Usage  Show Model Limits
Hide Emails
Refresh Every ›      1 minute … 30 minutes
Launch at Login
─────
Diagnostics…
About
```

`Claude…` and `Cursor…` connect a tool that is not connected yet. Otherwise they run `Add Claude Account…` and `Add Cursor Account…`. `Disconnect Claude` and `Disconnect Cursor` appear only while that tool is connected, and hide its card. Codex has nothing to disconnect.

`Show Model Limits` is on by default and checked while on. Turning it off hides Claude's per-model meters in the card and in each saved account's line. It never changes the menu bar icon, which uses only the session and weekly windows. It is saved as `claudeShowsModelLimits` in user defaults.

`App Icon` picks the app icon colour. [App Icon](app-controls/02-app-icon.md) owns it.

`Diagnostics…` first explains what the export contains, then writes a redacted JSON file only if the user confirms. The report holds allowlisted fields, per-export account aliases, every limit window each account reported (its kind, its menu title and a used-share category: available, limited or exhausted), summarized freshness states and recent CodexPill workflow events. It never includes raw logs, auth JSON, snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, stable account IDs, prompt or session content, or raw stderr.

## Rendering

The menu is a native `NSMenu`. Each card is an `NSMenuItem` whose view is a `MenuCardItemView` hosting the SwiftUI `ToolCardView`, with the side menu as its submenu. `MenuCardItemView` draws the hover highlight, because AppKit draws none for view-based items. Views do no I/O: `MenuBarMenuState.toolSections` turns the state into one `ToolSection` per card.

## Validation Notes

`ToolSectionTests` cover the card model per state: order, hidden windows, titles and lines, plan tags, masked emails and moves. `MenuBarMenuBuilderTests` build the `NSMenu` and assert item titles, order, submenus and the action each item sends. Coordinator flows live in `MenuBarCoordinatorTests`.
