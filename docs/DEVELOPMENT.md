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

## Validation

Behavior and invariant requirements live in [VALIDATION.md](VALIDATION.md). Run
`make test` before opening a pull request.

## Local Assumptions

- Codex is installed as `com.openai.codex`.
- The primary live auth file is `~/.codex/auth.json`.
- Rate-limit reads come from local or remote `codex app-server` surfaces.
- Tuist must be installed locally before build validation can succeed.
- Privacy and data-handling expectations live in [PRIVACY.md](PRIVACY.md).
