# Next Steps

## Goal

Move CodexPill from a validated prototype to a normal product repo without throwing away what already works.

## What We Keep

- The current working menubar prototype
- The existing bootstrap notes in `docs/BOOTSTRAP.md`
- The current product focus: Codex account switching and rate-limit visibility

## Immediate Completed Step

- Put the project under git and save the current state to GitHub
- Ignore generated Tuist/Xcode/build artifacts so the repo only tracks source-of-truth files

## Recommended Next Steps

### 1. Promote product truth out of bootstrap

Create:

- `docs/PRD.md`
- `docs/ARCHITECTURE.md`

`docs/PRD.md` should capture the real product scope, users, workflows, non-goals, and the open questions the prototype exposed.

`docs/ARCHITECTURE.md` should describe the stable module boundaries:

- auth switching
- Codex app lifecycle control
- Codex app-server reads
- local snapshot/catalog persistence
- menu bar presentation/state

### 2. Fix the account domain model

The next product slice should define stable account identity and matching.

Questions to answer:

- What is the canonical identity of a saved Codex account?
- How does a live signed-in account map back to a stored snapshot?
- What happens when metadata changes or cannot be fetched?

### 3. Refactor the prototype boundary

Reduce the current orchestration load in:

- `Sources/Features/Accounts/MenuBarStore.swift`
- `Sources/App/CodexPillAppDelegate.swift`

Target direction:

- thin UI/menu layer
- application-level use cases for save/switch/refresh/sign-in-another flows
- infrastructure adapters for file I/O, process control, and app-server reads
- feature-oriented grouping for product logic and platform-oriented grouping for integrations

### 4. Add behavior tests before new breadth

Start with tests for:

- account identity matching
- switch-account flow
- refresh failure and timeout behavior
- persistence and migration behavior

Do not start with visual/UI tests.

### 5. Switch to issue-driven delivery

After `PRD` and architecture are written:

- create an implementation plan
- slice the work into small issues
- use one issue -> one branch -> one PR

## Suggested First Issues

1. Define stable account identity and matching rules
2. Continue extracting account orchestration from `MenuBarStore`
3. Add tests for switching and refresh behavior
4. Normalize naming and remove remaining legacy repo drift
