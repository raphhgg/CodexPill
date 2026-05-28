# Validation

CodexPill protects user trust by validating account switching, account storage,
remote-host operations, notification behavior, and privacy boundaries through
unit and integration tests.

## Validation Contract

- Tests and validation fixtures must not touch real user data or real product
  processes unless a live mutation scenario is explicitly opted into.
- Tests must use temporary paths, isolated app-support directories, injected
  clients, and fakes for process or SSH side effects.
- Auth snapshots, raw auth payloads, tokens, API keys, and device codes must not
  be logged, committed, or emitted in diagnostics.
- Product behavior that changes account state must have deterministic coverage
  near the owning feature boundary.
- UI copy and menu composition changes should be covered by menu projection or
  presentation tests where possible.

## Main Local Gate

Run the default test suite before shipping changes:

```bash
make test
```

## Product Invariants

### Account Catalog

- Saved account snapshots are stored in CodexPill-owned app-support state.
- Duplicate saved-account names are rejected before sign-in starts.
- Empty saved-account names are blocked before sign-in starts, with the user kept
  in the Add Account naming flow.
- Terminal Add Account failures clear pending state so the user is not trapped in
  repeated completion alerts.
- Removing an account that is active on a local or remote target signs that
  target out before deleting the saved snapshot.

### Account Switching

- Local switching writes the selected saved snapshot to the active Codex auth
  surface and requests a Codex app refresh or relaunch through an injected
  process client.
- Remote switching uses the configured SSH host adapter and verifies the
  expected account before presenting the host as active.
- Stale notification actions must re-check current availability before switching
  a local or remote target.

### Account Refresh

- Refresh reads account metadata and rate limits from the Codex app-server
  surface when available.
- Refresh failures preserve last-known account state and surface recoverable
  error information without blocking normal menu use.
- Saved account identity matching must avoid merging distinct accounts that only
  share ambiguous metadata.

### Remote Hosts

- Add Host validates SSH destination input before enabling continuation.
- Remote hosts must not be shown as connected when verification fails.
- Remote auth snapshots may only be copied to user-configured hosts selected by
  the user.

### Notifications

- Notification workflows respect the app's notification preferences and macOS
  authorization state.
- Account Available notifications are only for inactive fallback accounts
  becoming useful again; first-saved or already-active accounts must not trigger
  them.
- If app notification workflows are disabled, the menu exposes a simple Enable
  Notifications action.
- If macOS authorization is denied, Enable Notifications opens System Settings
  rather than pretending to grant permission itself.

### App Controls

- Launch at Login reflects the native macOS login-item state; CodexPill must not
  show it as enabled after a failed registration attempt.
- Enabling Launch at Login must require an explicit confirmation before
  CodexPill asks macOS to register the app as a login item.
- When macOS requires approval for the login item, the menu opens System Settings
  instead of pretending CodexPill can approve the permission itself.
- When the login item state is unavailable, the menu keeps the item unchecked
  and opens System Settings instead of leaving the user at a dead end.

### Privacy

- Logs and validation artifacts must redact private paths, raw auth material,
  token-like values, and account identifiers unless the value is already a
  synthetic fixture.
- Diagnostic exports must require explicit user confirmation before a support
  artifact is built or written; cancelling the disclosure must leave no exported
  report behind.
- Demo and screenshot data must use synthetic accounts, hosts, and emails.

### Token Usage

- Cached Token Usage buckets may be reused only when they cover the requested
  current period; the bucket labeled as today must match today's local usage
  window rather than the last day from a stale persisted cache.
