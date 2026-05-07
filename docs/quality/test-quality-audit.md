# CodexPill Test Quality Audit

This document records report-only quality contracts for CodexPill tests. It is
not a CI policy by itself; every gate or threshold needs explicit maintainer
approval before adoption.

## Coverage Contract Proposal

### Recommendation

Configure source coverage alongside mutation testing as a local, report-only
audit artifact. Coverage should answer whether important production files and
feature boundaries are exercised at all. It should not rank test usefulness by
itself and should not become a release gate until the maintainer approves a
specific policy later.

The existing Tuist/Xcode test flow can collect coverage without changing
production app behavior. `make test` already generates `CodexPill.xcodeproj`
with Tuist, runs the `CodexPill` scheme through `xcodebuild test`, and writes an
`.xcresult` bundle under `build/results/<agent>/CodexPill.xcresult`. Xcode can
collect coverage for that same test action by adding `-enableCodeCoverage YES`,
then `xcrun xccov` can read the resulting `.xcresult`.

### Proposed Artifact Shape

Recommended first command:

```bash
AGENT_NAME=symphony-RGR-249 make generate
mkdir -p build/results/symphony-RGR-249 build/reports/symphony-RGR-249
rm -rf build/results/symphony-RGR-249/CodexPill.xcresult
xcodebuild test \
  -project CodexPill.xcodeproj \
  -scheme CodexPill \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "build/DerivedData/symphony-RGR-249" \
  -resultBundlePath "build/results/symphony-RGR-249/CodexPill.xcresult" \
  -enableCodeCoverage YES \
  PRODUCT_BUNDLE_IDENTIFIER="com.raphhgg.codexpill.staging"
xcrun xccov view --report --files-for-target CodexPill.app \
  build/results/symphony-RGR-249/CodexPill.xcresult \
  > build/reports/symphony-RGR-249/coverage.txt
```

Recommended output paths:

- Raw Xcode result bundle:
  `build/results/<agent>/CodexPill.xcresult`
- Human-readable report:
  `build/reports/<agent>/coverage.txt`
- Optional later machine-readable report:
  `build/reports/<agent>/coverage.json`

Included scope for the first report:

- Production target: `CodexPill`
- Source roots: `Sources/App`, `Sources/Core`, `Sources/Features`, and
  `Sources/Platform`
- The report should be reviewed by feature boundary first, then by file. The
  first useful question is whether a boundary has any executable test contact,
  not whether the aggregate percentage went up.
- The command should use `--files-for-target CodexPill.app` so the first
  artifact omits `CodexPillTests.xctest` rows and focuses on production source
  files.

Excluded scope:

- `Tests/**`
- `Tools/**`, including `CodexPillProofEmitter`
- `Resources/**`
- Generated Xcode/Tuist project files, DerivedData, result bundles, screenshots,
  and validation artifacts under `build/**`
- Third-party package code, including Seal package internals

Keep this as a documented command first. Add a `make coverage` wrapper only
after the maintainer confirms that recurring local coverage reports are useful.

### How Coverage Complements Mutation Testing

Mutation testing and coverage answer different questions:

- Mutation testing asks whether existing tests detect meaningful behavior
  changes in a bounded source scope.
- Coverage asks whether important files and boundaries are exercised at all.
- Test-usefulness ranking asks whether a suite still protects product claims
  better than another proof layer, such as Seal runtime validation.

Coverage is useful as a blind-spot detector before mutation work. A file with no
coverage should usually not be first judged by mutation score, because there may
be no useful test harness touching it. Once a boundary has meaningful coverage,
mutation testing can probe whether those tests assert behavior instead of merely
executing code.

Coverage is a poor vanity metric for CodexPill. High line coverage can hide weak
assertions, overfit tests, and missing error paths. Low line coverage can be
acceptable for OS-adjacent UI glue, live-auth integration boundaries, or paths
that are safer to validate through injected seams and Seal scenarios. Reviewers
should read coverage as a map of attention, not as proof that the product is
safe.

### First Boundaries To Inspect

If coverage becomes part of the recurring quality workflow, inspect these
boundaries first:

- Account workflows and use cases:
  `Sources/Features/Accounts/Workflows` and
  `Sources/Features/Accounts/UseCases`
- Codex auth and app-server protocol boundaries:
  `Sources/Platform/Codex`
- Persistence and path safety:
  `Sources/Platform/Persistence` and `Sources/Core/Configuration`
- Remote host orchestration:
  `Sources/Features/Hosts` and `Sources/Platform/Hosts`
- Menu projection and action routing:
  `Sources/Features/MenuBar/Presentation` and
  `Sources/Features/MenuBar/Runtime`
- Validation safety surfaces that protect real user state:
  `Sources/App/ValidationAppBootstrap.swift` and
  `Sources/Features/*/Validation`

These areas match CodexPill's highest-risk contracts: auth switching, local and
remote state isolation, app-server parsing, destructive account actions, menu
action wiring, and validation harness safety.

### Explicit Deferrals

Do not add any of the following without a later maintainer decision:

- Hard line, branch, function, file, target, or project coverage thresholds
- CI coverage gates
- PR-blocking coverage deltas
- Public badges or scoreboards
- Claims that coverage proves test quality
- Automatic deletion or rewriting of tests based only on coverage output

The next reasonable slice, if approved, is a local `make coverage` wrapper that
generates the report shape above and documents any Xcode-version-specific
limitations discovered while running it.
