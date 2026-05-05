# Kite Adoption Plan

Kite is a local Swift codebase scanner that reports structural facts for agent workflows. CodexPill should use it as inspection context, not as a quality gate.

## Goals

- Give architecture, review, and test-quality sessions a fast structural map before source reading.
- Make large files, long functions, diagnostics, skipped files, and source/test split visible during planning.
- Keep Kite output non-authoritative: metrics suggest where to inspect, but they do not prove defects, drift, or refactor need.

## Non-Goals

- Do not fail CI because a file is large or a function is long.
- Do not treat Kite as a linter, score, recommendation engine, or architecture verifier.
- Do not commit generated Kite reports by default.
- Do not replace source reading, product docs, or validation contracts with Kite rankings.

## Initial Local Workflow

Run from the CodexPill repo:

```bash
mkdir -p build/kite
kite scan . --format json > build/kite/kite-report.json
```

If `kite` is not installed but the local Kite checkout exists, use:

```bash
mkdir -p build/kite
/Users/raphh/Projects/kite/.build/release/kite scan . --format json > build/kite/kite-report.json
```

Use the JSON report as input for agent skills. For quick human inspection, run Kite without `--format json`.

Reports should live under `build/kite/` or another ignored local artifact directory.

CodexPill includes `.kite.toml` so local scans focus on app-owned Swift code under `Sources/`, `Tests/`, and `Tools/` while excluding generated Tuist sources and build output.

## Shared Trial Skills

The first trial skills live in `agent-standards` because they are reusable Swift-codebase inspection workflows, not CodexPill product truth:

- `/Users/raphh/agent-standards/skills/kite-architecture-triage/SKILL.md`
- `/Users/raphh/agent-standards/skills/kite-review-context/SKILL.md`
- `/Users/raphh/agent-standards/skills/kite-test-suite-triage/SKILL.md`

CodexPill owns only the product-local Kite config and this adoption note.

### kite-architecture-triage

Run before `improve-architecture` or before refining architecture issues.

The skill should:

- run or consume `kite scan . --format json`;
- check scan trust: status, diagnostics, skipped files, config state, source/test split;
- select a small number of inspection targets from source rankings;
- read relevant architecture docs and selected source files before making architecture statements;
- output inspection targets, source-cited observations, confidence limits, and what Kite cannot prove.

Best CodexPill targets:

- account, host, menubar, validation, and Codex platform boundaries;
- files repeatedly touched by bug fixes;
- large feature coordinators or long workflow functions.

### kite-review-context

Run before or during PR review.

The skill should:

- consume a Kite JSON report and changed-file list;
- check whether changed Swift files are included and correctly classified;
- map changed files to Kite evidence when available;
- read changed source before review statements;
- output a changed-file metric match table and review-reading checklist.

This should augment `review`, not replace it.

### kite-test-suite-triage

Run after validation/test-heavy work or when test files become hard to maintain.

The skill should:

- focus on `Tests/**` rankings;
- identify large test files, long scenario builders, and dense test helpers;
- read tests before proposing extraction;
- distinguish useful scenario coverage from accidental test bulk.

This is especially relevant while CodexPill migrates live validation toward Seal-backed proof APIs.

## Automation Candidates

### Weekly Codex Automation

Run a non-blocking Kite snapshot weekly or after several merged PRs.

Notify only when something materially changes, such as:

- new scanner diagnostics;
- previously included source becoming skipped;
- a new file/function dominating rankings;
- suspicious source/test classification drift.

Do not notify for normal ranking churn.

### Architecture Session Preflight

Before a planned architecture session, run `kite-architecture-triage` and attach the summary to the thread.

This is useful when deciding which boundary to inspect first.

## CI Candidate

Start with a non-blocking PR artifact:

- run `kite scan . --format json`;
- upload `kite-report.json`;
- optionally print terminal output;
- fail only if Kite crashes or cannot scan the repo.

Do not fail CI on metric thresholds in v1. If CI enforcement is added later, it should cover scanner/report regressions, not subjective code-quality limits.

## Test Plan For Adoption

1. Run Kite locally on CodexPill and confirm the report completes without diagnostics that make the report untrustworthy.
2. Run `kite-architecture-triage` in one real `improve-architecture` session and compare whether it improved target selection.
3. Run `kite-review-context` in one PR review and confirm the review still reads source before findings.
4. Run `kite-test-suite-triage` in one test-suite triage pass and decide whether the test rankings produce actionable cleanup candidates.
5. Decide whether these shared trial skills need routing/adoption docs in `agent-standards`.

## Open Decisions

- Whether Kite should be installed locally as a dependency expectation or referenced as an optional tool.
- Whether CI should run Kite on every PR or only on scheduled/manual workflows.
- Whether Kite reports should become Symphony agent artifacts for implementation/review roles.
