# Menubar

The menubar feature owns the menu's composition: which sections appear, in what order, and what each card and side menu offers. The behavior behind each item belongs to its own feature doc.

## Main Menu

Top to bottom, nothing else:

1. One card per visible tool: `Claude`, `Codex`, `Cursor` by default. Separators sit between cards.
2. The app's own items:

   ```text
   ─────
   Settings…            ⌘,
   ─────
   Diagnostics…
   About
   ```

3. The status message, only while an account operation runs.
4. `Quit ⌘Q`

Settings live in their own window ([Settings Window](#settings-window)); the menu keeps the quick actions. A tool with nothing set up has no card. Codex has a card while it is signed in on this Mac. Claude and Cursor have one once connected ([Claude Usage](claude-usage.md), [Cursor Usage](cursor-usage.md)). `Settings › Providers` hides a card.

With no card at all, on a first run or with every tool hidden, the menu starts at `Settings…`, where `Accounts` signs in to Codex and connects Claude and Cursor. On a first run with nothing connected, launch asks once: `Sign in to Codex?` / `Sign in to Codex in your browser.`

The user orders the cards in `Settings › Providers`. The first card drives the menu bar icon ([Status Bar](status-bar.md)).

## Card

Every tool uses the same card. It is one hover cell with a side menu and no chevron.

- **Header.** The tool's monochrome mark, its name, and the plan tag on the right: `Pro x20` or `Pro x5` for Codex, `Max x20` or `Max x5` for Claude, `Pro` for Cursor. The marks come from Lobe Icons (MIT, see `THIRD_PARTY_NOTICES.md`).
- **Meters.** One per window the tool reports, shortest first, named by its length: `Session` (5 hours), `Weekly` (7 days), `Monthly` (28 to 31 days), or `Billing cycle` for Cursor. Any other length is titled by that length, such as `8 days`. Claude's per-model weekly limits follow `Weekly`, one meter each, titled `<model> this week`, such as `Fable this week`. The Claude side menu's `Show Fable Limits` hides them. A Codex Free account shows only `Monthly`. A window the tool does not report has no meter. Codex Pro and Pro Lite hide the session window. Each meter shows the bar with an even-pace tick placed by the window's real length, `11% used` on the left and `Resets in 2h53` in grey on the right. A reset more than a week away, and any billing cycle's, reads as a date: `Resets 30 Oct`. Meters follow the `Usage Bars` settings.
- **Credits.** One line before the reset row when the tool reports credits or paid usage: `62,498 credits` or `Unlimited credits` for Codex, `$12.40 of $50.00 extra usage` (or `$12.40 extra usage` with no cap) for Claude extra usage and Cursor on-demand. A balance shows whole credits, rounded down. Nothing reported means no line, never `0`. Credits never change a meter.
- **Codex resets.** `2 resets available` with `Next expires 5 Nov` on the right, or `Expires 5 Nov` for one credit ([Codex Reset Credits](codex-reset-credits.md)). Claude has no reset row.
- **Cursor.** An unlimited plan has no meter.
- **States.** A title and at most one short line replace or precede the meters:

  | State | Title | Line |
  |---|---|---|
  | Waiting for the first read, from the moment a tool is connected | `Waiting for Codex usage` (or the tool's name) | none |
  | Stale | none, meters dimmed | `As of 10:26` |
  | Read failed with an earlier reading | the failure title, meters dimmed | `As of 10:26` |
  | Read failed with no earlier reading | the failure title | the failure line |

  Failure titles come from `ProviderCopy`, for example `Can't reach Anthropic` / `Retrying in a few minutes.`, `Cursor is busy`, `Cursor isn't installed`, `Allow Keychain access`. A Codex reading older than two refreshes, and at least 15 minutes, is stale.
- **Action rows.** While a state lasts, one row sits under the card: `Allow Keychain Access…`.

## Side Menu

Hovering a card opens its side menu, which holds only:

1. The email of the account in use, checked and disabled. For Claude and Cursor it is the account of the last reading: their own app's sign-in, or rusage's own Claude sign-in.
2. Codex only, when the account has reset credits: `Use a Reset…`, then one disabled `Expires <date>` line per credit Codex listed ([Codex Reset Credits](codex-reset-credits.md)).

Everything else about accounts, ordering and model limits lives in `Settings › Providers`.

`Hide Emails` masks every email the menu, its alerts and the tooltip show: `alex.side@example.com` reads `al•••e@example.com`. The domain stays visible.

Every tool item carries a `ProviderMenuAction` and goes through `MenuBarCoordinator.performProviderAction(_:)`.

## App Items

`Settings…` (⌘,) opens the [Settings Window](#settings-window) once the menu has closed.

`Diagnostics…` first explains what the export contains, then writes a redacted JSON file only if the user confirms. The report holds allowlisted fields, per-export account aliases, every limit window each account reported (its kind, its menu title and a used-share category: available, limited or exhausted), summarized freshness states and recent rusage workflow events. The Codex account appears once, with role `active_local`. A signed-out Codex reports the decision reason `codex_signed_out`, and a sign-in records the menu events `codex_sign_in` and `codex_account_replaced`. It never includes raw logs, auth JSON, saved sign-ins, raw UserDefaults, emails, hostnames, local paths, tokens, stable account IDs, prompt or session content, or raw stderr.

## Settings Window

One window of stock controls, with a toolbar pane per group. The title names the pane, the window keeps one size, the largest pane's, so switching panes never resizes it, minimize and zoom are off, and it reopens on the pane shown last.

| Pane | Controls |
|---|---|
| General | `Refresh Every` (1 to 30 minutes), `Hide Emails`, `Theme` ([Theme](app-controls/02-theme.md)), `Launch at Login` ([Launch at Login](app-controls/01-launch-at-login.md)) |
| Providers | A sidebar of the providers added to rusage, in the menu's order, with each one's mark and account email (masked with Hide Emails). Drag, or `Move Up` and `Move Down` from the context menu or VoiceOver, reorders them; the first one shown drives the menu bar icon. `+` under the list adds one that isn't added yet, through its consent alert or sign-in; `−` removes the selected one after `Remove <name> from rusage?`: Claude and Cursor are disconnected, which also signs out of rusage's own sign-in, and Codex is hidden but stays signed in on this Mac. With nothing added, the detail says `Add a provider with +`. The selected one shows `Show in Menu Bar`, then `Account`: its email with `Signed in` beside it, and `From Claude Code` or `From the Cursor app` under it while rusage reads that tool's own sign-in, then its actions. Codex: `Use Another Account…`, which replaces the Codex sign-in on this Mac ([Accounts](accounts/01-add-account.md)), and `Sign Out…`, which signs Codex out on this Mac after a confirmation. Claude: `Use Another Account…`, rusage's own browser sign-in, then `Sign Out…` while that sign-in is in use, or `Disconnect` while Claude Code's is ([Claude Usage](claude-usage.md)). Claude adds `Options › Model Limits`. The pane remembers the provider shown last while rusage runs |
| Menu Bar | `Menu Bar Label`, `Icon Style`, `Reveal Shortcut` ([Status Bar](status-bar.md)) |
| Usage Bars | `% Used` or `% Left`, `Classic` or `Compact`, `Pace Markers`, `Session Color`, `Weekly Color`, `Same Color for Both`, `Use Theme Colors` |
| Token Usage | `Show` (`Graph, breakdown on hover`, `Graph and breakdown`, `Hidden`), `Chart`, `Breakdown` ([Token Usage](token-usage.md)) |

`Show in Menu Bar` is on while that provider's card shows:

- Turning off `Claude` or `Cursor` disconnects it: the card goes and nothing is read, with no alert. Turning it on connects, through its consent alert.
- Turning off `Codex` hides its card and stops the Codex reads. `auth.json` stays as it is. Turning it on shows the card and reads it again. When Codex is signed out, it signs in first.
- Every tool can be hidden. The menu bar icon then shows the app's own glyph, and the menu is the first-run one.

Settings that only store a value bind straight to `SettingsModel`, so the menu follows at once. Switches with side effects (connect and disconnect, Launch at Login, the shortcut, Token Usage) go through `MenuBarCoordinator`, the same path the menu takes. While the window shows, rusage has a Dock icon so the window can come forward. Closing the window drops its content, so nothing observes the settings while it is closed.

## Rendering

The menu is a native `NSMenu`. Each card is an `NSMenuItem` whose view is a `MenuCardItemView` hosting the SwiftUI `ToolCardView`, with the side menu as its submenu. `MenuCardItemView` draws the hover highlight, because AppKit draws none for view-based items. Views do no I/O: `MenuBarMenuState.toolSections` turns the state into one `ToolSection` per card.

## Validation Notes

`ToolSectionTests` cover the card model per state: order, hidden windows, titles and lines, plan tags, masked emails and moves. `MenuBarMenuBuilderTests` build the `NSMenu` and assert item titles, order, submenus and the action each item sends. Coordinator flows live in `MenuBarCoordinatorTests`. The builder tests also open the Settings window, check its panes, and close it.
