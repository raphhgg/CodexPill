# Remote Hosts

Remote Hosts owns configuring SSH targets, installing saved account snapshots on those targets, switching remote Codex accounts, and verifying the remote active account.

Remote install state is freshness-aware. A saved account is considered installed on a host only when the cached remote snapshot matches the current local saved snapshot. If the remote cache is missing or stale, CodexPill reinstalls the snapshot before switching so old refresh tokens are not copied back into the remote Codex auth state.

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
- Body: `Enter the SSH destination CodexPill should use, for example user@host.`
- Optional name label: `Host Name (Optional)`
- Destination label: `SSH Destination`
- Idle status: `CodexPill checks the connection automatically.`
- Success status: `Connection successful.`
- Actions: `Cancel`, `Add Host`

## SSH Destination Contract

CodexPill accepts the same destination strings OpenSSH accepts for a normal host target, including SSH config aliases such as `workstation` and explicit destinations such as `user@host`.

The destination is valid only when it already works from the user's environment with non-interactive SSH. CodexPill runs SSH with `BatchMode=yes` and does not collect, store, or prompt for SSH passwords, key passphrases, host-key trust prompts, 2FA, or SSH configuration.

Users own custom ports and advanced SSH options through `~/.ssh/config`. CodexPill does not parse raw SSH flags in the destination field.

## Validation Feedback

The destination field starts neutral. After the user pauses typing, CodexPill may show validation feedback:

- Neutral/checking while validation is pending.
- Error styling for invalid or unreachable destinations.
- Unknown hostnames or missing SSH config aliases show `Host not found. Check the hostname or SSH config alias.`
- SSH setup failures such as missing credentials, host-key prompts, 2FA, password prompts, passphrase prompts, or connectivity failures show `SSH is not ready for CodexPill. Set up SSH access, then try again.`
- Success styling when the host is reachable.

`Add Host` unlocks only when the destination is valid.

Validation still checks remote Codex readiness after SSH connects; a host must have Codex available and writable CodexPill/Codex directories, not merely SSH reachability.

## Install And Switch Follow-Up

After a host validates, CodexPill asks whether to install and switch the current account on that host.

Copy:

- Title pattern: `Install current account on <Host Name>?`
- Body pattern: `Install <Account Name> on <Host Name> and switch the host to it now? If you cancel, the host will not be added yet.`
- Primary action: `Install and Switch`
- Secondary action: `Cancel`

If the user cancels this follow-up, CodexPill should not leave a confusing pending host state. The host should either not be added yet or the UI must clearly explain what remains incomplete.

## Acceptance Criteria

- Add Host validates destination feedback and unlocks `Add Host` only for a
  reachable Codex-ready SSH target.
- Host setup can install and switch the current account, or leave no confusing
  pending host state when cancelled.
- Failed or ambiguous remote verification is surfaced and is not presented as a
  verified active account.
- Remote account cards prefer verified remote values and use saved-account
  fallback only when remote data is missing or suspicious.

## Validation Scenario Candidates

- `remote-host-add-panel-validation`
- `remote-host-install-switch-current-account`
- `remote-host-verification-failure`
- `remote-host-rate-limit-fallback`

## Validation Intent

Primary proof for `remote-host-add-panel-validation`: `contract-fixture`

Supporting proof for `remote-host-add-panel-validation`: `unit`

Product scenario:

- `remote-host-add-panel-validation` proves that Add Host stays disabled until
  destination validation succeeds for the same trimmed destination, that
  validation feedback remains actionable for unknown host, non-interactive SSH,
  unreachable SSH, and not-Codex-ready failures, and that the SSH validation
  contract checks Codex CLI/app-server readiness plus writable CodexPill/Codex
  directories.

Required evidence:

- focused suite output from `MenuBarHostSetupFormStateTests`,
  `MenuBarAlertFactoryTests`, and `SSHRemoteHostClientTests`;
- `build/verification/remote-host-add-panel-validation/contract-receipt.json`;
- `build/verification/remote-host-add-panel-validation/scenario-summary.json`.

Non-claims:

- This scenario does not prove native Add Host panel screenshot rendering, first
  responder focus, click automation, live SSH, live Codex app-server behavior,
  real remote filesystem mutation, or the install-and-switch follow-up.

Live opt-in: not required for this scenario.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Add Host validates destination feedback and unlocks `Add Host` only for reachable Codex-ready targets. | `contract-fixture` plus `unit` | `make verify-remote-host-add-panel-validation-scenario` running `MenuBarHostSetupFormStateTests`, `MenuBarAlertFactoryTests`, and `SSHRemoteHostClientTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/remote-host-add-panel-validation/contract-receipt.json`, and `scenario-summary.json`. | Invalid, unreachable, not-Codex-ready, and successful destinations map to the documented feedback states; `Add Host` unlocks only for successful Codex-ready validation of the same trimmed destination; SSH validation uses non-interactive BatchMode and checks Codex app-server readiness plus writable CodexPill/Codex directories. | Synthetic destinations and fake command results only; no raw SSH output, private hostnames, usernames, paths, tokens, or auth payloads. |
| Host setup installs and switches the current account, or leaves no confusing pending host state when cancelled. | `workflow-event-log` | Host setup coordinator test with fake remote operations and cancel branch. | Structured host setup receipt. | Confirming runs install then switch in order; cancelling creates no ambiguous pending host or records an explicit incomplete state visible to the user. | Fake remote host and auth snapshots only; redact raw SSH output, auth payloads, tokens, private paths, emails, and hostnames. |
| Failed or ambiguous remote verification is surfaced and not shown as verified active state. | `unit` plus `deterministic-ui` | Remote verification failure tests and menu projection assertion. | Failure result bundle plus optional hosted menu artifact. | Ambiguous/mismatched verification surfaces recovery state and the menu does not show the remote card as verified active. | Synthetic host/account data only; no raw SSH output, auth payloads, tokens, private paths, emails, or hostnames. |
| Remote cards prefer verified remote values and use saved fallback only when remote data is missing or suspicious. | `unit` plus `contract-fixture` | Rate-limit resolution tests with verified, missing, and suspicious remote fixtures. | Resolution fixture result bundle. | Verified remote values win; fallback values are labeled/presented only as fallback and never as verified remote truth. | Synthetic rate-limit payloads only; no real account ids, emails, hostnames, raw SSH output, auth payloads, or tokens. |

## Validation Targets

- Panel presentation tests for Add Host field states and validation feedback.
- Fake SSH/Codex readiness contract fixtures for reachable, unreachable,
  host-key prompt, credential prompt, not-Codex-ready, and success branches.
- Workflow-event tests for install-and-switch ordering and cancel behavior.
- Unit/menu projection tests for remote verification failure states.
- Contract fixtures for remote rate-limit fallback resolution.
