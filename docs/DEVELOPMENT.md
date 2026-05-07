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

Deterministic UI validation:

```bash
make verify-ui
```

Live menubar validation:

```bash
make verify-ui-live
```

Seal-only account-switch runtime validation:

```bash
swift run --package-path ../Seal seal run --scenario switch-account-changes-active-account
```

Seal-only Add Host validation-failure runtime validation:

```bash
swift run --package-path ../Seal seal run --scenario add-host-destination-validation-failed
```

Those shorter commands resolve the CodexPill adapter from `.seal/run.yml` and
use Seal's default artifact layout under `build/seal-runs/<scenario>/...`. The
Make targets remain as compatibility entry points for agents that need a stable
`build/verification/<agent>/<scenario>/` artifact root.

## Validation Artifacts

`make verify-ui` renders deterministic menu states from fixtures and writes screenshot plus JSON artifacts under `build/verification/<agent>/<scenario>/`.

`make verify-ui-live` launches the real menubar app in validation mode, waits for the app to emit `live-menu-snapshot.json` during menu rebuild, asserts menu-item metadata such as enabled state and action wiring from that runtime snapshot, then adds an Accessibility probe plus screenshot as supporting proof.

Behavior and invariant requirements live in [VALIDATION.md](VALIDATION.md).

## Local Assumptions

- Codex is installed as `com.openai.codex`.
- The primary live auth file is `~/.codex/auth.json`.
- Rate-limit reads come from local or remote `codex app-server` surfaces.
- Tuist must be installed locally before build validation can succeed.
- Privacy and data-handling expectations live in [PRIVACY.md](PRIVACY.md).
