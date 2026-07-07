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

Primary proof for `remote-host-install-switch-current-account`: `workflow-event-log`

Supporting proof for `remote-host-install-switch-current-account`: `contract-fixture`

Primary proof for `remote-host-verification-failure`: `unit`

Supporting proof for `remote-host-verification-failure`: menu projection

Primary proof for `remote-host-rate-limit-fallback`: `contract-fixture`

Supporting proof for `remote-host-rate-limit-fallback`: `unit`

Product scenarios:

- `remote-host-add-panel-validation` proves that Add Host stays disabled until
  destination validation succeeds for the same trimmed destination, that
  validation feedback remains actionable for unknown host, non-interactive SSH,
  unreachable SSH, and not-Codex-ready failures, and that the SSH validation
  contract checks Codex CLI/app-server readiness plus writable CodexPill/Codex
  directories.
- `remote-host-install-switch-current-account` proves that the Add Host
  follow-up either installs and switches the current active account on the
  validated host in order, then persists verified host/account state, or leaves
  no pending host state when the follow-up is cancelled.
- `remote-host-verification-failure` proves that different, ambiguous, failed,
  or unreadable remote verification is represented as failed/unverified host
  state, never as a verified active remote account, while detected accounts stay
  recoverable through host management instead of replacing saved catalog truth.
- `remote-host-rate-limit-fallback` proves that verified remote rate-limit
  values win when meaningful, while missing, zeroed, partial, expired, or
  suspicious remote values fall back to meaningful saved-account windows scoped
  by canonical saved identity instead of email alone.

Required evidence:

- for Add Host validation, focused suite output from `MenuBarHostSetupFormStateTests`,
  `MenuBarAlertFactoryTests`, and `SSHRemoteHostClientTests`;
- Kite scenario receipt for `remote-host-add-panel-validation`.
- for install-and-switch follow-up, focused suite output from
  `MenuBarRuntimeValidationTests`, `SwitchAccountOnHostWorkflowTests`, and
  `MenuBarAlertFactoryTests`;
- Kite scenario receipt for `remote-host-install-switch-current-account`.
- for verification failure, focused suite output from
  `RemoteHostAccountVerifierTests`, `RemoteHostRuntimeTests`,
  `SwitchAccountOnHostWorkflowTests`, `MenuBarMenuStateTests`, and
  `MenuBarMenuBuilderTests`;
- Kite scenario receipt for `remote-host-verification-failure`.
- for rate-limit fallback, focused suite output from
  `RemoteRateLimitResolutionTests`, `MenuBarAccountCatalogProjectionTests`,
  `MenuBarMenuStateTests`, and `MenuBarRuntimeValidationTests`;
- Kite scenario receipt for `remote-host-rate-limit-fallback`.

Non-claims:

- The Add Host validation scenario does not prove native Add Host panel
  screenshot rendering, first responder focus, click automation, live SSH, live
  Codex app-server behavior, real remote filesystem mutation, or the
  install-and-switch follow-up.
- The install-and-switch follow-up scenario does not prove native Add Host or
  confirmation panel rendering, focus, click automation, live SSH, live Codex
  app-server behavior, real remote auth mutation, real remote filesystem
  mutation, or remote verification failure presentation.
- The verification failure scenario does not prove live SSH, live Codex
  app-server behavior, real remote auth mutation, real remote filesystem
  mutation, native click automation, live menu-bar interaction, or remote
  rate-limit fallback.
- The rate-limit fallback scenario does not prove live SSH, live Codex
  app-server behavior, real remote auth mutation, real remote filesystem
  mutation, native click automation, live menu-bar interaction, or final native
  menu pixels for fallback labels.

Live opt-in: not required for these scenarios.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Add Host validates destination feedback and unlocks `Add Host` only for reachable Codex-ready targets. | `contract-fixture` plus `unit` | `make verify-remote-host-add-panel-validation-scenario` running `MenuBarHostSetupFormStateTests`, `MenuBarAlertFactoryTests`, and `SSHRemoteHostClientTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Invalid, unreachable, not-Codex-ready, and successful destinations map to the documented feedback states; `Add Host` unlocks only for successful Codex-ready validation of the same trimmed destination; SSH validation uses non-interactive BatchMode and checks Codex app-server readiness plus writable CodexPill/Codex directories. | Synthetic destinations and fake command results only; no raw SSH output, private hostnames, usernames, paths, tokens, or auth payloads. |
| Host setup installs and switches the current account, or leaves no confusing pending host state when cancelled. | `workflow-event-log` plus `contract-fixture` | `make verify-remote-host-install-switch-current-account-scenario` running `MenuBarRuntimeValidationTests`, `SwitchAccountOnHostWorkflowTests`, and `MenuBarAlertFactoryTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Confirming records install, switch, app-server refresh, and status verification in order for the current active account, then persists desired account, verified account, verified status, and installed account id; cancelling creates no pending host state. | Fake remote host, fake command/client results, and synthetic auth snapshots only; no raw SSH output, auth payloads, tokens, private paths, emails, or hostnames. |
| Failed or ambiguous remote verification is surfaced and not shown as verified active state. | `unit` plus menu projection | `make verify-remote-host-verification-failure-scenario` running `RemoteHostAccountVerifierTests`, `RemoteHostRuntimeTests`, `SwitchAccountOnHostWorkflowTests`, `MenuBarMenuStateTests`, and `MenuBarMenuBuilderTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Ambiguous, mismatched, failed, or unreadable verification clears verified active state, stores failure/detected-account recovery state, keeps failed hosts out of primary active remote cards, and does not replace the saved account catalog. | Synthetic host/account/status data only; no raw SSH output, auth payloads, tokens, private paths, emails, or hostnames. |
| Remote cards prefer verified remote values and use saved fallback only when remote data is missing or suspicious. | `contract-fixture` plus `unit` | `make verify-remote-host-rate-limit-fallback-scenario` running `RemoteRateLimitResolutionTests`, `MenuBarAccountCatalogProjectionTests`, `MenuBarMenuStateTests`, and `MenuBarRuntimeValidationTests`. | `build/results/local/CodexPill.xcresult` and Kite scenario receipt. | Verified remote values win when meaningful; saved fallback windows are used only for missing, zeroed, partial, expired, or suspicious remote data; fallback matching is scoped by canonical saved identity; remote cards and validation summaries expose meaningful fallback limits without claiming live SSH proof. | Synthetic rate-limit payloads only; no real account ids, emails, hostnames, raw SSH output, auth payloads, or tokens. |

## Validation Targets

- Panel presentation tests for Add Host field states and validation feedback.
- Fake SSH/Codex readiness contract fixtures for reachable, unreachable,
  host-key prompt, credential prompt, not-Codex-ready, and success branches.
- Workflow-event tests for install-and-switch ordering and cancel behavior.
- Unit/menu projection tests for remote verification failure states.
- Contract fixtures for remote rate-limit fallback resolution.
