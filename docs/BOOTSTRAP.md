# Bootstrap

## Product Pitch

CodexPill is a macOS menubar app that snapshots Codex accounts, swaps the active Codex auth state, restarts Codex, and reads the current Codex account plan and 5h/weekly rate-limit windows from the local Codex app-server.

## Selected Shape

- Native macOS SwiftUI menubar app
- Tuist-managed app target
- Prototype-first bootstrap

## Demo Flows

1. Save the currently logged-in Codex account as a named snapshot and fetch its current email, plan, and rate-limit windows from Codex.
2. Switch the active Codex account by replacing `~/.codex/auth.json` with a saved snapshot and relaunching Codex.
3. View the current 5h and weekly Codex rate-limit windows in the menubar popup and refresh them from Codex.

## Non-Goals

- No ChatGPT browser-account switching.
- No scraping-heavy telemetry pipeline in the first prototype.
- No multi-window preferences UI unless the menubar surface becomes too constrained.

## Current Run Command

```bash
./scripts/run_menubar.sh
```

The local build loop is shell-first:

- `tuist generate --no-open`
- `xcodebuild build/test`
- `./scripts/run_menubar.sh`
- `make verify-ui`
- `make verify-ui-live`

`make verify-ui` is the hosted deterministic validator. It renders menu states from fixtures and writes screenshot plus JSON artifacts under `build/verification/<agent>/<scenario>/`.

`make verify-ui-live` is the live smoke validator. It launches the real menubar app in validation mode, waits for the app to emit `live-menu-snapshot.json` during menu rebuild, then adds an Accessibility probe plus screenshot as supporting proof.

Generated `.xcodeproj` and `.xcworkspace` files are transient build artifacts for the shell workflow, not source-of-truth files to open in Xcode during normal development.

## Current Stop Command

```bash
./scripts/stop_menubar.sh
```

## Constraints And Assumptions

- Codex is installed as `com.openai.codex`.
- The primary auth file is `~/.codex/auth.json`.
- Rate-limit reads come from the local `codex app-server` interface.
- Tuist must be installed locally before build validation can succeed.

## Next Recommended Step

Improve account matching so refreshed Codex metadata is associated by stable account identity rather than whichever snapshot is currently active.
