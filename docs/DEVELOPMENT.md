# Development

## Project Shape

- Platform: native macOS menubar app.
- UI: SwiftUI and AppKit through `MenuBarExtra`, `NSMenu`, `NSAlert`, and SwiftUI-backed panels.
- Build system: Tuist.
- Primary local workflow: shell-first, not Xcode-first.

Generated `.xcodeproj` and `.xcworkspace` files are transient build artifacts for the shell workflow, not source-of-truth files to open in Xcode during normal development.

## Commands

Generate the project without opening Xcode:

```bash
tuist generate --no-open
```

Build:

```bash
make build
```

Package a local release zip:

```bash
make package-release
```

`make package-release` builds `CodexPill.app` in Release configuration and, by
default, requires local Developer ID signing and notarization configuration
before it creates a public release artifact. Configure these environment
variables locally:

- `RELEASE_VERSION`: public release tag, for example `v0.1.0-beta.1`. Packaging
  uses this for the artifact name and injects it into the app so `About` shows
  the released version instead of `Dev`.
- `DEVELOPER_ID_APPLICATION`: Developer ID Application signing identity name or
  SHA-1 hash.
- `APPLE_TEAM_ID`: Apple Developer team ID.
- `NOTARY_PROFILE`: local `notarytool` keychain profile name.

Create the notary profile with `xcrun notarytool store-credentials
<profile-name>`. Do not commit Apple IDs, passwords, API keys, keychain exports,
or signing credentials.

For build and zip validation only, run:

```bash
PACKAGE_RELEASE_ALLOW_UNSIGNED=1 make package-release
```

Unsigned validation artifacts are marked `UNSIGNED-LOCAL` and are not public
beta release artifacts. Dirty working trees are refused by default. For local
validation only, `PACKAGE_RELEASE_ALLOW_DIRTY=1` allows the command to continue
and marks the artifact name with `DIRTY`.

The first public beta was published as
[`v0.1.0-beta.1`](https://github.com/raphhgg/CodexPill/releases/tag/v0.1.0-beta.1).
Future public beta releases should use the same signed/notarized artifact path
until release automation replaces the manual GitHub Release flow.

Test:

```bash
make test
```

Run:

```bash
./scripts/run_menubar.sh
```

Stop:

```bash
./scripts/stop_menubar.sh
```

Reset local state before testing the signed release install:

```bash
./scripts/reset_release_test_state.sh
./scripts/reset_release_test_state.sh --apply --install
```

The reset script is dry-run by default. It removes CodexPill app state,
preferences, local build artifacts, and isolated temporary login homes. With
`--remote <host>` it also removes the `~/.codexpill` cache that earlier versions
copied to an SSH host. Use `--remote-sign-out` only when you intentionally want
to remove that host's active Codex login.

## Isolated Launch

Run a dev build without touching your real `~/.codex` login or your real
CodexPill data:

```bash
make build AGENT_NAME=<name>
root="$(mktemp -d)"
open -n \
  --env CODEXPILL_ISOLATED_APP_SUPPORT_DIR="$root" \
  --env CODEXPILL_ISOLATED_DEFAULTS_SUITE="codexpill-isolated-${root##*/}" \
  --env CODEX_HOME="$root" \
  build/DerivedData/<name>/Build/Products/Debug/CodexPill.app
```

- `CODEXPILL_ISOLATED_APP_SUPPORT_DIR` holds the account catalog, saved
  snapshots, the token-usage cache, and the live `auth.json` that switching
  writes.
- `CODEXPILL_ISOLATED_DEFAULTS_SUITE` keeps preferences out of the real
  `UserDefaults` domain.
- `CODEX_HOME` points the `codex app-server` that CodexPill starts at the same
  `auth.json`.
- Claude usage reads `.credentials.json` from `CLAUDE_CONFIG_DIR`, or from
  `<root>/.claude`, and never the Keychain. CodexPill's own Claude sign-in is
  kept in memory only. "Sign in with Claude" still opens the real browser, so
  do not finish it with a real account. Claude account switching is off.
- Cursor usage reads `<root>/Cursor/state.vscdb`, never Cursor's real database.
  Cursor account switching is off, so an isolated run never quits Cursor.

Switching still asks the real Codex app to relaunch. Quit the isolated app by
its process ID, not with `scripts/stop_menubar.sh`, which stops every running
CodexPill.

## Validation

[VALIDATION.md](VALIDATION.md) lists the automated gate, `make test`, and a short
manual checklist. Run `make test` before opening a pull request.

## Local Assumptions

- Codex is installed as `com.openai.codex`.
- The primary live auth file is `~/.codex/auth.json`.
- Rate-limit reads come from the local `codex app-server`.
- Tuist must be installed locally before build validation can succeed.
- Privacy and data-handling expectations live in [PRIVACY.md](PRIVACY.md).
