# First Signed Beta Release Checklist

This checklist is the human release gate for the first signed CodexPill public
beta. Run it from a clean `main` checkout after the signed GitHub Release zip
packaging path, public install docs, license, and security policy have landed.

Do not publish an unsigned artifact as the recommended beta download. Do not
record Apple account identifiers, signing credential values, keychain profile
secrets, or raw notarization credentials in public release notes, issue
comments, or repo files.

## Release Candidate

Record these values before packaging:

| Field | Evidence |
| --- | --- |
| Release version | `Project.swift` `CFBundleShortVersionString`: `0.1.0` |
| Build number | `Project.swift` `CURRENT_PROJECT_VERSION`: `1` |
| Source branch | `main` |
| Source commit | |
| GitHub Release tag | `v0.1.0-beta.1` |
| Zip artifact name | |
| GitHub Release URL | |

Confirm the working tree is clean and points at the intended public source:

```bash
git switch main
git pull --ff-only origin main
git status --short
git log -1 --oneline
```

`git status --short` must print no tracked or untracked release inputs outside
ignored build output.

## Build, Sign, And Notarize

Run the signed packaging command with local signing and notarization configured
outside the repo:

```bash
AGENT_NAME=release RELEASE_VERSION=v0.1.0-beta.1 make package-release
```

The command must build `CodexPill.app`, sign it with Developer ID Application,
enable hardened runtime, submit for notarization, staple the ticket, validate
the staple, run Gatekeeper assessment, and create the release zip under
`build/release/artifacts/`.

Record summarized evidence only:

| Check | Evidence |
| --- | --- |
| Release build produced `CodexPill.app` | |
| Zip contains `CodexPill.app` | |
| `codesign --verify --deep --strict --verbose=2` passed | |
| Hardened runtime confirmed from `codesign --display --verbose=4` | |
| `xcrun notarytool submit --wait` succeeded | |
| `xcrun stapler staple` succeeded | |
| `xcrun stapler validate` passed | |
| `spctl --assess --type execute --verbose=4` accepted the app | |

Use `unzip -l <artifact.zip>` to confirm the zip contains `CodexPill.app`.

## GitHub Release

Create the GitHub Release from the same commit recorded above. Attach the signed
zip artifact and include release notes that match the public install path.

Release notes should include:

- The artifact is a signed and notarized beta zip containing `CodexPill.app`.
- Codex must already be installed and signed in on the Mac.
- CodexPill stores saved account snapshots locally.
- Remote-host support copies selected snapshots only to configured hosts.
- Homebrew, Sparkle, and Mac App Store distribution are not available for this
  beta.

Release notes must not include signing credentials, Apple account details,
private machine paths, local keychain profile names, auth snapshots, tokens, or
personal fixture data.

## Fresh Download Smoke

After publishing, download the artifact from the GitHub Release into a fresh
temporary directory, unzip it, and launch that downloaded copy.

Record:

| Check | Evidence |
| --- | --- |
| Download URL | |
| Downloaded zip filename | |
| Unzip produced `CodexPill.app` | |
| Downloaded app launched without Gatekeeper bypass | |
| Menubar item appeared | |
| README install instructions matched the published artifact | |

Do not mark the release complete until the freshly downloaded artifact launches.

## Repo Safety Check

Before announcing the beta, confirm the public repo and release notes do not
include secrets, private paths, personal fixture data, generated auth snapshots,
or unsigned release artifacts.

Suggested checks:

```bash
git status --short
git diff --check
rg -n --hidden --glob '!.git/**' --glob '!build/**' --glob '!*.xcodeproj/**' \
  'BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|AKIA[0-9A-Z]{16}|xox[baprs]-|ghp_[A-Za-z0-9_]{30,}|notarytool store-credentials|~/Library/Application Support/Codex/|~/.codex/auth.json'
```

The grep may match documentation that names safe paths or commands. Review each
match and record whether it is safe documentation or a blocker.

## Deferrals

Track any unfinished release work as explicit deferrals or follow-up issues.
Known deferrals for the first beta path:

- Homebrew cask.
- Sparkle update feed.
- CI release automation.
- Mac App Store distribution.

Hidden blockers are not acceptable. If signing, notarization, stapling,
Gatekeeper assessment, GitHub Release upload, or fresh-download launch fails,
stop the release and file a follow-up with the failing command, summarized
output, and recovery action.
