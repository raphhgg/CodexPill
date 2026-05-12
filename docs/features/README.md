# Features

Feature docs are organized by product feature area. Each area can contain behavior contracts, UX contracts, and validation notes.

## Feature Areas

- [Menubar](menubar.md): whole menu composition, section ordering, and App Controls placement.
- [Status Bar](status-bar.md): closed-state icon, label, hover behavior, and usage indicators.
- [Accounts](accounts/00-accounts.md): saved accounts, current account, switching, adding, removing, renaming, and account refresh.
- [Remote Hosts](remote-hosts.md): host setup, remote account install/switch, verification, and remote account presentation.
- [Notifications](notifications.md): notification modes, permission recovery, delivery copy, actions, and dedupe behavior.
- [Release](release/01-signed-github-zip.md): public beta distribution contract for the signed/notarized GitHub Release zip.
- [First Signed Beta Release Checklist](release/03-first-beta-release-checklist.md): maintainer release gate and evidence template for the first signed beta.
- [Screenshot Demo Data](release/02-screenshot-demo-data.md): sanitized workflow for public release screenshots.

## Ownership Rule

Feature behavior belongs in the owning feature area. Shared surfaces, such as the menubar, should document composition and link to the owning feature for behavior.
