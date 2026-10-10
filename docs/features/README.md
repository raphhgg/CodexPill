# Features

Feature docs are organized by product feature area. Each area can contain behavior contracts, UX contracts, and validation notes.

## Feature Areas

- [Menubar](menubar.md): whole menu composition, section ordering, and App Controls placement.
- [Status Bar](status-bar.md): closed-state icon, label, hover behavior, and usage indicators.
- [Accounts](accounts/00-accounts.md): saved accounts, current account, switching, adding, removing, renaming, and account refresh.
- [Remote Hosts](remote-hosts.md): host setup, remote account install/switch, verification, and remote account presentation.
- [Notifications](notifications.md): notification modes, permission recovery, delivery copy, actions, and dedupe behavior.
- [Claude Usage](claude-usage.md): opt-in, read-only Claude 5-hour and weekly limits, read with CodexPill's own "Sign in with Claude" or, as a fallback, Claude Code's sign-in.
- [Cursor Usage](cursor-usage.md): opt-in Cursor plan usage, on-demand spend, and billing-cycle reset, plus saving and switching Cursor sign-ins.
- [Token Usage History](token-usage.md): opt-in local Codex token usage card and its source contract.
- [Token Usage Incremental Cache](token-usage-cache.md): persistent cache and background scanner contract for large local Codex histories.
- [Token Usage Loading Progress](token-usage-loading-progress.md): honest animated loading feedback while first local scans are still running.
- [App Controls](app-controls/01-launch-at-login.md): app-level controls that do not belong to accounts, hosts, notifications, or status-bar presentation.
- [Release](release/01-signed-github-zip.md): public beta distribution contract for the signed/notarized GitHub Release zip.
- [First Signed Beta Release Checklist](release/03-first-beta-release-checklist.md): maintainer release gate and evidence template for the first signed beta.
- [Swift 6 Language Mode Migration](release/04-swift-6-language-mode.md): engineering quality contract for compiling app and test targets in Swift 6 language mode.

## Ownership Rule

Feature behavior belongs in the owning feature area. Shared surfaces, such as the menubar, should document composition and link to the owning feature for behavior.
