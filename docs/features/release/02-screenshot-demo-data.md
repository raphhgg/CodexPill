# Screenshot Demo Data

Public release screenshots must be produced from CodexPill's hosted validation
fixture, not from the maintainer's real Codex state. The fixture is synthetic,
test-only, and rendered under `build/` so it stays separate from production
account data.

## Demo Workflow

From a clean checkout, run:

```bash
AGENT_NAME=screenshot-demo make verify-ui
```

The default scenario is `release-demo-screenshot`. It writes a temporary
validation request to `build/verification/request.json`, renders the screenshot
fixture, and stores generated artifacts under:

```text
build/verification/release-demo-screenshot/
```

The useful files are:

- `screenshots/release-demo-screenshot.png`
- `ui-tree.json`
- `scenario-summary.json`

Generated screenshot artifacts are build output. Do not commit them unless a
future issue explicitly asks for release-image assets.

## Screenshot Fixture

The release screenshot scenario lives in
`Tests/MenuBar/MenuBarUIValidationTests.swift` under
`release-demo-screenshot`. It uses only synthetic values:

| Surface | Value |
| --- | --- |
| Local active account | `Atlas Local` |
| Local email | `atlas.local@example.com` |
| Local plan | `pro` |
| Local usage | Session `24%`, weekly `41%` |
| Remote host | `demo-buildbox` |
| Remote destination | `demo-user@demo-buildbox` |
| Remote active account | `Orion Remote` |
| Remote email | `orion.remote@example.com` |
| Remote plan | `team` |
| Remote usage | Session `18%`, weekly `52%` |
| Other saved accounts | `Nova Research`, `Echo Sandbox`, `Backup Demo` |

Rate-limit reset times are derived from the fixed validation clock used by the
test harness, so future renders are repeatable. Emails must stay on
`example.com`, hostnames must remain demo-only, and the fixture must never use a
real `~/.codex/auth.json`, SSH destination, token, or auth snapshot.

## Safety Boundary

This is not a public demo mode. The scenario is reachable through the test
target and `make verify-ui`; normal app launches and production persistence do
not load this data. The workflow does not require:

- real Codex auth tokens;
- a real local `~/.codex/auth.json`;
- real SSH credentials;
- CodexPill app-support data from the maintainer's machine.

To reset after a screenshot run, remove the generated validation output:

```bash
rm -rf build/verification
```

Normal CodexPill runtime returns to real local state by launching the app through
the regular `make run` or `./scripts/run_menubar.sh` path without a validation
request.

## Pre-Publish Check

Before publishing screenshots, inspect `ui-tree.json` and
`scenario-summary.json` and confirm they contain no maintainer email domains,
real hostnames, private paths, or auth payloads. Human review of the final demo
names and usage values is required before release images are published.
