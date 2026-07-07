# Status Bar

The status bar feature owns CodexPill's closed-state menubar presentation: icon, label, hover behavior, and compact usage indicators.

## Purpose

The status bar gives the user a lightweight answer before opening the menu: which account is active and whether its limits look healthy.

## Owned Surface

- App icon or monochrome menubar icon.
- Optional label text.
- Hover-expanded and shortcut-revealed text behavior.
- Compact session/weekly indicators.
- The `Preferences` submenu exposes `Menu Bar Label`, `Icon Style`, and `Usage Bars` controls for label mode, the reveal shortcut, icon style, pacing marker visibility, and accent color. App-level controls in the same submenu are owned by their own feature docs.
- Tooltip text.

## Menu Bar Label Reveal Shortcut

CodexPill ships with the global shortcut `⌃⌥⌘L` while the app is running.
Pressing it temporarily reveals the same status item label that appears on hover
for about three seconds without opening the menu and without changing the saved
`Menu Bar Label` display mode. Pressing the shortcut again while the label is
visible collapses it.

Users can configure the shortcut from:

```text
Preferences
  Menu Bar Label
    Reveal Shortcut…    ⌃⌥⌘L
```

If a configured shortcut cannot be registered, CodexPill keeps the previous
working shortcut and shows an error.

## Relationship To Accounts

The status bar consumes account availability data, but account identity, switching, and refresh behavior remain owned by [Accounts](accounts/00-accounts.md).

## Relationship To Menubar

The status bar opens the menubar popup, whose composition is owned by [Menubar](menubar.md).

## Acceptance Criteria

- The closed-state status item renders a visible icon and optional label.
- Hovering inside the status item bounds expands the label and leaving the
  bounds collapses it.
- The reveal shortcut temporarily shows the label without changing the saved
  display mode, and pressing it again collapses the label.
- Preferences control menu-bar label mode, icon style, usage bar pacing
  markers, and accent colors without changing account state.

## Validation Scenario Candidates

- `status-bar-icon-text-visible`
- `status-bar-hover-label`
- `status-bar-shortcut-reveal`
- `status-bar-usage-bars-preferences`

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| The closed-state status item renders a visible icon and optional label. | `unit` plus `deterministic-ui` | `StatusItemRuntimeTests.iconAndTextPresentationProducesVisibleTitleSnapshot()` and `make verify-ui SCENARIO=status-bar-icon-text-visible`. | Runtime-state snapshot in `build/verification/status-bar-icon-text-visible/status-item-state.json`, plus `ui-tree.json` and `scenario-summary.json`. | The status item runtime snapshot shows a visible icon-and-text state with displayed title `S 42% W 68%` for synthetic active-account usage. The deterministic scenario does not prove live menubar screen capture, native hittability, hover expansion, shortcut reveal, temporal behavior, or multiple-display layout behavior. | Synthetic account state only; no raw auth payloads, tokens, account identifiers, private paths, emails, hostnames, or prompts. |
| Hover expands and leave collapses the label. | `workflow-event-log` with optional future `live-ui-smoke` | `make verify-status-bar-hover-label-scenario` running `StatusItemRuntimeTests` and `MenuBarRuntimeValidationTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/status-bar-hover-label/workflow-receipt.json`, and `scenario-summary.json` with `proofSequence`. | Text-on-hover starts hover polling; the fake-runtime sequence records hover polling enabled, hover enter, title visible, hover exit scheduled, hover exited, and title hidden; saved display mode is unchanged. The deterministic scenario does not prove native mouse movement, real pointer bounds, native hover activation or exit timer cadence, live menubar screen capture, native hittability, or multiple-display layout behavior. | Synthetic account/status-title fixtures only; no raw auth payloads, tokens, account identifiers, private paths, emails, hostnames, or prompts. |
| The reveal shortcut temporarily shows the label and repeat press collapses it. | `workflow-event-log` | `make verify-status-bar-shortcut-reveal-scenario` running `StatusItemRuntimeTests`, `GlobalShortcutRuntimeTests`, and `MenuBarRuntimeValidationTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/status-bar-shortcut-reveal/workflow-receipt.json`, and `scenario-summary.json` with `proofSequence`. | Fake global shortcut callbacks reach the coordinator; the fake-runtime sequence records callback forwarded, reveal started, title visible, repeat press, reveal ended, and title hidden; saved display mode remains unchanged. The deterministic scenario does not prove live Carbon/global hotkey registration, native keyboard input, system shortcut conflicts, native reveal timer cadence, live menubar capture, or native hittability. | Synthetic account/status-title/shortcut fixtures only; no raw shortcut recorder logs, auth payloads, tokens, account identifiers, private paths, emails, hostnames, or prompts. |
| Preferences update status-bar presentation without changing account state. | `unit` plus `deterministic-ui` | `make verify-status-bar-usage-bars-preferences-scenario` running `StatusItemSettingsStoreTests`, `CodexPillSettingsStoreTests`, `MenuBarMenuBuilderTests`, `MenuBarSnapshotExtractionTests`, and `MenuBarRuntimeValidationTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/status-bar-usage-bars-preferences/workflow-receipt.json`, and `scenario-summary.json`. | Label mode, icon style, usage-bar pacing markers, and accent color update presentation settings and semantic menu snapshot rows only; coordinator preference actions preserve the account catalog, active-account ID, and auth-file bytes. The deterministic scenario does not prove live color-panel choice, native menu-bar clicks, live menubar capture, or native hittability. | Synthetic account/usage data only; artifacts must not include raw auth, tokens, paths, emails, hostnames, or account identifiers. |

## Validation Targets

- Projection or runtime-state tests for icon and optional label visibility.
- Fake pointer-event tests for hover expansion and collapse, backed by ordered
  proof-sequence metadata rather than final-state-only assertions.
- Fake shortcut-clock tests for reveal/collapse behavior, backed by ordered
  proof-sequence metadata rather than final-state-only assertions.
- Preference mapping tests for label mode, icon style, pacing markers, and
  accent colors.
- Optional live UI smoke only when a scenario declares explicit opt-in,
  cleanup, privacy rules, and non-claims.

## Degraded Proof And Non-Claims

The current runnable Status Bar scenarios are deterministic and product-local.
They do not exercise live pointer movement, native global-hotkey registration,
native timer cadence, native status item hittability, live menubar screen
capture, multiple-display menu-bar layout, or notch behavior.

Busy menu status is owned by [Menubar](menubar.md), and Token Usage loading
progress is owned by [Token Usage Loading Progress](token-usage-loading-progress.md).
Status Bar scenarios may consume usage percentages for icon rendering, but they
must not claim animated busy/progress timing unless a separate status-bar
runtime behavior and explicit live or temporal proof contract are added.
