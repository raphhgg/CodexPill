# Development

## Project Shape

- Platform: native macOS menubar app.
- UI: SwiftUI and AppKit through `MenuBarExtra`, `NSMenu`, `NSAlert`, and SwiftUI-backed panels.
- Build system: Tuist.
- Primary local workflow: shell-first, not Xcode-first.

Generated `.xcodeproj` and `.xcworkspace` files are transient build artifacts for the shell workflow, not source-of-truth files to open in Xcode during normal development.

## Rename From CodexPill

Refill was called CodexPill before. Every identifier moved to the new name: the
`com.raphhgg.refill` bundle IDs, `~/Library/Application Support/Refill`,
`~/Library/Caches/Refill`, the `Refill …` Keychain items and the `REFILL_*`
environment variables.

`CodexPillMigration` (`Sources/Platform/Persistence`) runs once at launch,
before anything reads the catalog or settings. It copies
`Application Support/CodexPill` to `Application Support/Refill` when Refill has
no data yet (no folder, or only an empty `[]` catalog and empty `snapshots`),
copies preferences from the CodexPill domain of the same build
(`com.raphhgg.codexpill` for release, `com.raphhgg.codexpill.dev` for
`make build`) without overwriting set keys. It leaves out
`claude-code-accounts.json` and the `claude-sign-in` and `cursor-sign-in` folders
a test build may have left, and copies no Keychain items. It never changes
CodexPill's copies. The
`codexPillMigrationDone` preference records that it ran. A failure is logged and
shown once. Isolated runs skip it. [Uninstall And Reset](UNINSTALL_RESET.md)
explains how to remove what CodexPill left.

The GitHub repository is `raphhgg/Refill`. The Homebrew cask is still
`raphhgg/tap/codexpill` until the first Refill release renames it to `refill`. A
release installed before the rename is `CodexPill.app`.

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

`make package-release` builds `Refill.app` in Release configuration and, by
default, requires local Developer ID signing and notarization configuration
before it creates a public release artifact. Configure these environment
variables locally:

- `RELEASE_VERSION`: public release tag, for example `v0.1.0-beta.1`. Packaging
  uses this for the artifact name, `Refill-<version>.zip`, and injects it into
  the app so `About` shows the released version instead of `Dev`.
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
[`v0.1.0-beta.1`](https://github.com/raphhgg/Refill/releases/tag/v0.1.0-beta.1).
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

The reset script is dry-run by default. It removes Refill app state,
preferences, local build artifacts, and isolated temporary login homes. With
`--remote <host>` it also removes the `~/.codexpill` cache that earlier versions
copied to an SSH host. Use `--remote-sign-out` only when you intentionally want
to remove that host's active Codex login.

## Isolated Launch

Run a dev build without touching your real `~/.codex` login or your real
Refill data:

```bash
make build AGENT_NAME=<name>
root="$(mktemp -d)"
open -n \
  --env REFILL_ISOLATED_APP_SUPPORT_DIR="$root" \
  --env REFILL_ISOLATED_DEFAULTS_SUITE="refill-isolated-${root##*/}" \
  --env CODEX_HOME="$root" \
  build/DerivedData/<name>/Build/Products/Debug/Refill.app
```

- `REFILL_ISOLATED_APP_SUPPORT_DIR` holds the account catalog, saved
  snapshots, the token-usage cache, and the live `auth.json` that switching
  writes.
- `REFILL_ISOLATED_DEFAULTS_SUITE` keeps preferences out of the real
  `UserDefaults` domain.
- `CODEX_HOME` points the `codex app-server` that Refill starts at the same
  `auth.json`.
- Claude usage reads `.credentials.json` from `CLAUDE_CONFIG_DIR`, or from
  `<root>/.claude`, and never the Keychain. Refill's own Claude sign-in lives
  in `<root>/claude-sign-in.json` (0600) with its lock in
  `<root>/claude-sign-in.lock`, never in the Keychain. `Sign in with Claude…`
  still opens the real browser and a loopback port.
- Cursor usage reads `<root>/Cursor/state.vscdb`, never Cursor's real database.
- Token Usage reads Codex sessions from `<root>/sessions`, never
  `~/.codex/sessions`.

Switching still asks the real Codex app to relaunch. Quit the isolated app by
its process ID, not with `scripts/stop_menubar.sh`, which stops every running
Refill. It does not stop an older `CodexPill.app`.

## Validation

[VALIDATION.md](VALIDATION.md) lists the automated gate, `make test`, and a short
manual checklist. Run `make test` before opening a pull request.

## Local Assumptions

- Codex is installed as `com.openai.codex`.
- The primary live auth file is `~/.codex/auth.json`.
- Rate-limit reads come from the local `codex app-server`.
- Tuist must be installed locally before build validation can succeed.
- Privacy and data-handling expectations live in [PRIVACY.md](PRIVACY.md).
