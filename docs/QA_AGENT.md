# Agent QA Plan

## Goal

Exercise the current `CodexPill` behavior from an agent workflow and distinguish product regressions from unrelated Codex plugin or app-server noise.

## Preconditions

- Build from the current working tree with `./scripts/run_menubar.sh`.
- Use a fresh `xcodebuild` result bundle path for any test run.
- If Codex plugin-manifest warnings appear on stderr, log them separately unless they block a product workflow.

## Baseline Verification

1. Run:

   ```bash
   xcodebuild test \
     -project /Users/raphaelgrau/Projects/codex-usage-menubar-app/CodexPill.xcodeproj \
     -scheme CodexPill \
     -destination 'platform=macOS' \
     -resultBundlePath /tmp/codexpill-agent-qa.xcresult
   ```

2. Confirm all tests pass.
3. If the build fails only because the result bundle path already exists, rerun with a new path.

## Runtime Smoke

1. Launch the app with:

   ```bash
   ./scripts/run_menubar.sh
   ```

2. Confirm:
   - the app appears in the menu bar
   - startup completes without the store getting stuck busy
   - account load finishes and the menu renders

3. Capture repo-standard validation artifacts:

   ```bash
   make verify-ui
   make verify-ui-live
   ```

4. Confirm the artifact directories contain:
   - hosted screenshots and `ui-tree.json` fixtures for deterministic menu states
   - a live `live-menu-snapshot.json` emitted by the running app
   - a live screenshot and `summary.json`

## Workflow Smoke

Run the workflows in this order:

1. Save current account
   - save with a custom name
   - save with a blank custom name and verify email fallback naming
   - confirm the account list stays sorted

2. Switch account
   - switch to another saved account
   - confirm the warning text references the target account
   - confirm active account state updates after the switch

3. Refresh account data
   - refresh the active account
   - confirm plan, email, and rate-limit data update
   - confirm status returns to ready after completion

4. Sign in another account
   - start the sign-in-another flow
   - complete sign-in
   - confirm the pending account is persisted once and becomes active

5. Settings
   - change refresh interval
   - change visible inactive account count
   - change status bar indicator style
   - confirm the menu/status item reflects the new values

## Failure Paths

Verify:

- duplicate account names are rejected
- canceling a confirmation path does not mutate state
- refresh failures produce one user-facing error and do not leave the store busy
- sign-in-another failures do not duplicate accounts

## Refactor Regression Checks

Verify:

- `MenuBarStore` still owns observable feature state only
- `LoadAccountsUseCase` handles bootstrap/load/reconcile/active-account derivation
- `RefreshActiveAccountUseCase` handles remote refresh/match/persist behavior
- `MenuBarCoordinator` still reacts correctly to store and settings changes
- menu and alert helper output still matches expectations

## Known Noise To Separate

- Plugin manifest warnings from Codex plugin loading are not `CodexPill` failures by themselves.
- Current known product bug:
  `CodexPill` treats any `codex app-server` stderr output as a fatal error, even when stderr only contains warnings.
  Refresh-related QA should account for that and log it as an app bug, not as random Codex instability.

## Cleanup

1. Stop the app with:

   ```bash
   ./scripts/stop_menubar.sh
   ```

2. Confirm no stray `CodexPill` process remains.
