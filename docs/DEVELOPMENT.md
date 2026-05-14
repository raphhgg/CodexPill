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

## Validation

Behavior and invariant requirements live in [VALIDATION.md](VALIDATION.md). Run
`make test` before opening a pull request.

## Local Assumptions

- Codex is installed as `com.openai.codex`.
- The primary live auth file is `~/.codex/auth.json`.
- Rate-limit reads come from local or remote `codex app-server` surfaces.
- Tuist must be installed locally before build validation can succeed.
- Privacy and data-handling expectations live in [PRIVACY.md](PRIVACY.md).
