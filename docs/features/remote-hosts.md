# Remote Hosts

Remote Hosts owns configuring SSH targets, installing saved account snapshots on those targets, switching remote Codex accounts, and verifying the remote active account.

## Entry Points

- `Hosts` in the App Controls section.
- Active account cards in `Active Account(s)` when a host is connected, verified, and has a resolved active account.
- Per-account submenu actions such as `Switch on <host>` or `Install on <host> and switch`.

## Add Host Panel

Component: SwiftUI-backed `NSPanel`.

Purpose:

- Capture an optional display name and required SSH destination.
- Validate the destination before enabling the final add action.
- Keep host setup visually aligned with the Add Account sign-in panel.

Layout contract:

- Window title: `Add remote host`
- App icon appears in the panel header area.
- Host name field appears first but is optional.
- SSH destination field appears second and should receive initial focus.
- Fields and labels are left-aligned.
- Status text appears below the SSH field.
- Bottom actions are right-aligned.

Copy:

- Title: `Add remote host`
- Body: `Enter the SSH destination for the host you want CodexPill to target, for example user@host.`
- Optional name label: `Host Name (Optional)`
- Destination label: `SSH Destination`
- Idle status: `CodexPill checks the connection automatically.`
- Success status: `Connection successful.`
- Actions: `Cancel`, `Add Host`

## Validation Feedback

The destination field starts neutral. After the user pauses typing, CodexPill may show validation feedback:

- Neutral/checking while validation is pending.
- Error styling for invalid or unreachable destinations.
- Success styling when the host is reachable.

`Add Host` unlocks only when the destination is valid.

## Install And Switch Follow-Up

After a host validates, CodexPill asks whether to install and switch the current account on that host.

Copy:

- Title pattern: `Install current account on <Host Name>?`
- Primary action: `Install and Switch`
- Secondary action: `Cancel`

If the user cancels this follow-up, CodexPill should not leave a confusing pending host state. The host should either not be added yet or the UI must clearly explain what remains incomplete.
