# Signed GitHub Release Zip

## User Story

As a macOS Codex user trying CodexPill for the first time, I want to download a
release artifact from GitHub that macOS can verify, so I can evaluate the app
without building from source or bypassing scary Gatekeeper warnings.

## Product Contract

The first public beta distribution channels are:

- a signed and notarized GitHub Release `.zip` containing `CodexPill.app`;
- a Homebrew cask that installs the same signed and notarized release artifact.

The release artifact must be built from the public `main` branch, signed with a
Developer ID Application certificate, use hardened runtime, pass Apple
notarization, have the notarization ticket stapled, and be attached to a GitHub
Release.

Homebrew must consume the same signed/notarized artifact as the GitHub Release.
It must not build from source or point at an unsigned app.

## Happy Path

1. Maintainer bumps the app version/build number from the repo-owned source of
   truth.
2. Maintainer runs `make package-release` from a clean `main` checkout with
   `RELEASE_VERSION` set to the public tag, for example `v0.1.0-beta.1`.
3. Packaging builds `CodexPill.app` in release configuration.
4. Packaging signs the app with Developer ID and hardened runtime.
5. Packaging submits the app for notarization.
6. Packaging staples the notarization ticket.
7. Packaging injects the release version into the copied app bundle so `About`
   displays the public release version.
8. Packaging creates a `.zip` containing `CodexPill.app`.
9. Maintainer creates a GitHub Release and attaches the zip.
10. Maintainer updates the Homebrew cask to point at the released artifact.
11. A user installs via Homebrew or downloads, unzips, and launches CodexPill
   without manual Gatekeeper
   bypass instructions.

## UI / Copy / States

README install copy should be direct:

```md
brew install --cask raphhgg/tap/codexpill

Or download the latest signed beta from GitHub Releases.
```

If signed/notarized artifacts are not available yet, README copy must say:

```md
Signed beta downloads are not available yet. Build from source for now.
```

The README should include a short first-run note:

- Codex must already be installed.
- CodexPill reads local Codex auth state and stores saved account snapshots
  locally.
- Remote-host support copies selected snapshots only to hosts the user configures.

## Edge Cases

- If signing credentials are unavailable, the release must not be presented as a
  downloadable public beta.
- If notarization fails, do not attach the artifact as the recommended install
  path.
- If Gatekeeper assessment fails on a downloaded zip, the release is not ready.
- If the artifact is built from dirty local state, the release is invalid.
- Signing credentials, API keys, Apple IDs, keychain exports, and notary
  credentials must never be committed.
- If the Homebrew cask points at a stale or unsigned artifact, do not announce
  the release until the cask is corrected.

## Acceptance Criteria

- A clean `main` checkout can produce `CodexPill.app` in release configuration.
- `make package-release` produces a `.zip` artifact containing
  `CodexPill.app`.
- The app is signed with Developer ID Application identity.
- Hardened runtime is enabled for the signed app.
- Apple notarization succeeds.
- The notarization ticket is stapled.
- `spctl`/Gatekeeper assessment accepts the final app artifact.
- The GitHub Release contains the zip artifact and release notes.
- The Homebrew cask points at the same signed/notarized artifact.
- README install instructions match the real install paths.
- No signing credentials or notarization secrets are stored in the repo.

## Validation Targets

- Local release packaging dry run from a clean checkout.
- Signing verification with `codesign --verify`.
- Notarization verification with `xcrun notarytool`.
- Stapling verification with `xcrun stapler validate`.
- Gatekeeper verification with `spctl`.
- Manual download-and-launch smoke test from the GitHub Release artifact.
- Homebrew install smoke test for the published cask.
- Repo safety grep for secrets, private paths, and personal fixture data before
  publishing.

## Out Of Scope / Deferrals

- Sparkle auto-updates.
- Mac App Store distribution.
- Unsigned beta artifacts.
- Automated CI release publishing unless manual packaging proves stable first.

## Settled Release Decisions

- The first public beta uses the maintainer's Developer ID Application
  certificate and a local `notarytool` keychain profile.
- `make package-release` is the repeatable local packaging command.
- The release version is provided through `RELEASE_VERSION` and injected into
  the copied app bundle so `About` shows the public release version.
- GitHub Release and Homebrew cask publishing are currently manual maintainer
  steps after the signed/notarized zip is produced and verified.

## Recommended Next Checkpoint

Automate GitHub Release and Homebrew cask publishing once the manual signed zip
flow has stayed stable across beta releases.

## Related Release Workflows

- [First Signed Beta Release Checklist](03-first-beta-release-checklist.md):
  maintainer release gate and evidence template for the first signed beta.
