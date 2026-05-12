# Signed GitHub Release Zip

## User Story

As a macOS Codex user trying CodexPill for the first time, I want to download a
release artifact from GitHub that macOS can verify, so I can evaluate the app
without building from source or bypassing scary Gatekeeper warnings.

## Product Contract

The first public beta distribution channel is a signed and notarized GitHub
Release `.zip` containing `CodexPill.app`.

The release artifact must be built from the public `main` branch, signed with a
Developer ID Application certificate, use hardened runtime, pass Apple
notarization, have the notarization ticket stapled, and be attached to a GitHub
Release.

Homebrew is intentionally deferred until a stable signed/notarized release
artifact exists. The README must not document a Homebrew install path until the
cask exists and has been exercised.

## Happy Path

1. Maintainer bumps the app version/build number from the repo-owned source of
   truth.
2. Maintainer runs `make package-release` from a clean `main` checkout.
3. Packaging builds `CodexPill.app` in release configuration.
4. Packaging signs the app with Developer ID and hardened runtime.
5. Packaging submits the app for notarization.
6. Packaging staples the notarization ticket.
7. Packaging creates a `.zip` containing `CodexPill.app`.
8. Maintainer creates a GitHub Release and attaches the zip.
9. A user downloads, unzips, and launches CodexPill without manual Gatekeeper
   bypass instructions.

## UI / Copy / States

README install copy should be direct:

```md
Download the latest signed beta from GitHub Releases.
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
- If Homebrew is added later, it must consume the same signed/notarized artifact
  rather than building from source or pointing at an unsigned app.

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
- README install instructions match the real artifact and do not mention
  Homebrew as available.
- No signing credentials or notarization secrets are stored in the repo.

## Validation Targets

- Local release packaging dry run from a clean checkout.
- Signing verification with `codesign --verify`.
- Notarization verification with `xcrun notarytool`.
- Stapling verification with `xcrun stapler validate`.
- Gatekeeper verification with `spctl`.
- Manual download-and-launch smoke test from the GitHub Release artifact.
- Repo safety grep for secrets, private paths, and personal fixture data before
  publishing.

## Out Of Scope / Deferrals

- Homebrew cask.
- Sparkle auto-updates.
- Mac App Store distribution.
- Unsigned beta artifacts.
- Automated CI release publishing unless manual packaging proves stable first.

## Open Questions

- Which Apple Developer team ID and signing identity will be used?
- Where will notarization credentials live locally or in CI?
- What exact version/build-number source of truth should packaging use?
- Should the first beta release be manual-only, or should we immediately add a
  repeatable `make package-release` command?
- What screenshot/demo-data workflow must be completed before the first release
  page is public?

## Recommended Next Checkpoint

Use `create-issues` after approving this contract. The first implementation
slice should produce a repeatable local packaging command and documentation for
the signed/notarized GitHub zip path.

## Related Release Workflows

- [Screenshot Demo Data](02-screenshot-demo-data.md): sanitized fixture and
  validation workflow for public screenshots.
