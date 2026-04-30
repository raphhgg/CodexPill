# Human QA Plan

Human QA is residual in this repo. If an agent can prove a behavior through tests or live smoke, that behavior belongs in [VALIDATION.md](/Users/raphh/Projects/CodexPill/docs/VALIDATION.md), not here.

## Use Human QA Only For

- native alert copy and text-entry UX that current automation does not drive
- real Codex sign-in completion across external app surfaces
- wake or longer-running lifecycle behavior not yet covered by a dedicated smoke
- OS-level focus, permission, or pointer-control issues that block live agent proof

## Setup

1. Launch the app:

   ```bash
   ./scripts/run_menubar.sh
   ```

2. If available, run the automated proof first:

   ```bash
   make verify-ui
   make verify-ui-live
   ```

3. Use manual QA only for the specific residual gap that automation did not cover.

## Residual Checks

### 1. Alert And Prompt UX

Verify:

- Add Account prompts show the expected copy
- duplicate-name rejection is understandable to a human and returns the app to a stable state

### 2. Real Sign-In-Another Flow

Verify:

- the external Codex sign-in flow completes successfully after the prompt is confirmed
- the resulting account is captured once
- the new account becomes active without duplication

### 3. Timer And Lifecycle Behavior

Verify:

- the app recovers correctly after wake or longer-running idle periods

### 4. Manual Recovery From OS-Level Issues

Verify:

- the app remains usable if accessibility, pointer control, or focus behavior interferes with live smoke
- failures can be classified as product issues vs environment issues

## Out Of Scope

- behaviors already covered by unit, integration, deterministic UI, or live smoke validation
- Codex plugin marketplace or plugin-loader warnings by themselves
- unrelated Codex desktop network sync issues unless they block a `CodexPill` workflow

## What To Capture If Something Fails

- the exact residual manual scenario you exercised
- what automation already proved before manual QA started
- what you expected
- what actually happened
- whether the app recovered after reopening the menu
- whether the failure is repeatable
