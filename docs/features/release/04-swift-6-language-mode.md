# Swift 6 Language Mode Migration

## User Story

As a CodexPill maintainer, I want the app and test targets to compile in Swift
6 language mode so concurrency diagnostics are enforced as build errors before
they can become release risk.

## Product Contract

CodexPill continues to behave the same for account switching, remote hosts,
token usage, notifications, and release packaging, while the source target and
test target build with `SWIFT_VERSION = 6.0` under the installed Swift 6.3
toolchain.

The migration must not add unsafe concurrency escape hatches unless a narrow
safety invariant is documented next to the code. The default fix should be
explicit actor isolation and provable `Sendable` conformance for immutable
value-style dependencies.

## Happy Path

1. The project is generated from Tuist.
2. The app target compiles with Swift 6 language mode.
3. Production concurrency diagnostics in account workflows and token usage
   progress reporting are resolved without changing user-facing behavior.
4. The test target compiles with Swift 6 language mode.
5. The full local test suite passes.

## UI / Copy / States

No user-facing UI, copy, or menu-state changes are expected.

## Edge Cases

- Account workflow dependencies currently stored on `@MainActor`
  `AccountsController` must not be sent across async boundaries unless the
  compiler can prove they are safe.
- Token usage progress callbacks must not capture mutable actor-isolated state
  from detached work.
- Test probes and fixtures must not hide real data-race risks with broad
  `@unchecked Sendable` conformances.
- Migration validation must not read from or write to real Codex auth snapshots,
  tokens, or production CodexPill user data.
- Swift 6.3 is the installed compiler version; the project language setting is
  still Swift 6.0.

## Acceptance Criteria

- `Project.swift` or generated build settings opt the app target into Swift 6
  language mode.
- The app target builds with no Swift 6 concurrency errors.
- The test target builds with Swift 6 language mode enabled.
- `make test` passes with Swift 6 language mode enabled.
- Existing product behavior covered by tests remains unchanged.
- No new broad `@unchecked Sendable`, `nonisolated(unsafe)`, or
  `@preconcurrency` workaround is introduced without a local safety invariant
  and a reason it is narrower than an actor-isolation or value-conformance fix.

## Validation Targets

- Capture the baseline Swift 6 diagnostic list before fixing.
- Run a Swift 6 app build and confirm the current known diagnostics are gone:
  `AccountsController` stored workflow/use-case sends and
  `TokenUsageMenuRuntime` detached progress callback capture.
- Run `make test`.
- Review changed concurrency boundaries for task lifetime, cancellation, actor
  isolation, and `Sendable` correctness.
- Confirm validation artifacts do not print auth payloads, tokens, account
  identifiers, or saved snapshot contents.

## Out Of Scope / Deferrals

- Adopting new Swift 6.3 language features beyond what is required for Swift 6
  language-mode correctness.
- Re-architecting account switching, remote-host switching, token usage
  scanning, or release packaging.
- Changing menu UX or adding visible migration status.
- Converting all unstructured tasks to structured concurrency unless required
  by Swift 6 diagnostics or a directly touched safety invariant.

## Open Questions

- Should Swift 6 mode land for app and test targets in one PR, or should the
  app target land first with a follow-up for tests if test harness changes
  expand unexpectedly?

## Recommended Next Checkpoint

Create one implementation issue from this contract. The first execution slice
should enable Swift 6 mode locally, fix production diagnostics, then expand to
the test target only after the app target is green.
