#!/usr/bin/env node
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";

const scenarioTargets = {
  "add-account-failure-cleanup": "verify-add-account-failure-cleanup-scenario",
  "add-account-isolated-success": "verify-add-account-isolated-success-scenario",
  "add-account-name-validation": "verify-add-account-name-scenario",
  "diagnostics-export-confirmation": "verify-diagnostics-export-confirmation-scenario",
  "hosted-menu-default": "verify-ui",
  "launch-at-login-blocked-opens-settings": "verify-launch-at-login-blocked-opens-settings-scenario",
  "launch-at-login-enable-confirmation": "verify-launch-at-login-enable-confirmation-scenario",
  "launch-at-login-menu-states": "verify-ui",
  "menu-account-overflow": "verify-ui",
  "menu-busy-status": "verify-ui",
  "menu-empty-catalog": "verify-ui",
  "menu-unmatched-active-account": "verify-ui",
  "notifications-account-available-policy": "verify-notifications-account-available-policy-scenario",
  "notifications-current-runs-out-action": "verify-notifications-current-runs-out-action-scenario",
  "notifications-dedupe-after-delivery": "verify-notifications-dedupe-after-delivery-scenario",
  "notifications-permission-denied-menu-state": "verify-notifications-permission-denied-menu-state-scenario",
  "refresh-active-relinks-same-account": "verify-refresh-active-relinks-same-account-scenario",
  "refresh-inactive-isolated-status": "verify-refresh-inactive-isolated-status-scenario",
  "remote-host-add-panel-validation": "verify-remote-host-add-panel-validation-scenario",
  "remote-host-install-switch-current-account": "verify-remote-host-install-switch-current-account-scenario",
  "remote-host-rate-limit-fallback": "verify-remote-host-rate-limit-fallback-scenario",
  "remote-host-verification-failure": "verify-remote-host-verification-failure-scenario",
  "remove-account-active-targets-sign-out": "verify-remove-account-active-targets-sign-out-scenario",
  "remove-account-signout-failure-keeps-control": "verify-remove-account-signout-failure-keeps-control-scenario",
  "rename-account-label-only": "verify-rename-scenario",
  "status-bar-hover-label": "verify-status-bar-hover-label-scenario",
  "status-bar-icon-text-visible": "verify-ui",
  "status-bar-shortcut-reveal": "verify-status-bar-shortcut-reveal-scenario",
  "status-bar-usage-bars-preferences": "verify-status-bar-usage-bars-preferences-scenario",
  "switch-account-local-confirmed": "verify-switch-account-local-confirmed-scenario",
  "switch-account-remote-install-verify": "verify-switch-account-remote-install-verify-scenario",
  "token-usage-cache-first": "verify-token-usage-cache-scenario",
  "token-usage-loading-progress": "verify-ui",
  "token-usage-off-hidden": "verify-ui",
  "token-usage-parser-aggregation": "verify-token-usage-parser-scenario",
  "token-usage-privacy-no-raw-session": "verify-token-usage-privacy-scenario",
  "token-usage-ready-card": "verify-ui"
};

const request = await readScenarioRequest();
const scenarioId = request?.scenario?.id ?? process.env.KITE_SCENARIO_ID ?? process.env.SCENARIO;

if (typeof scenarioId !== "string" || scenarioId.length === 0) {
  fail("KITE_SCENARIO_REQUEST, KITE_SCENARIO_ID, or SCENARIO must name a scenario id.");
}

const target = scenarioTargets[scenarioId];
if (target === undefined) {
  fail(`Unsupported CodexPill Kite scenario: ${scenarioId}`);
}

const exitCode = await runMakeTarget(target, scenarioId).catch(() => {
  fail("Could not start CodexPill scenario make target.");
});
process.exit(exitCode);

async function readScenarioRequest() {
  const requestPath = process.env.KITE_SCENARIO_REQUEST;
  if (requestPath === undefined || requestPath.length === 0) {
    return undefined;
  }

  let request;
  try {
    request = JSON.parse(await readFile(requestPath, "utf8"));
  } catch {
    fail("Could not read Kite scenario request.");
  }
  if (request.kind !== "kite_scenario_command_request") {
    fail(`Unsupported Kite scenario request kind: ${request.kind}`);
  }
  if (request.schemaVersion !== "kite.validation.scenario-command-request.v1") {
    fail(`Unsupported Kite scenario request schema: ${request.schemaVersion}`);
  }
  return request;
}

function runMakeTarget(target, scenarioId) {
  return new Promise((resolve, reject) => {
    const child = spawn("make", [target], {
      env: {
        ...process.env,
        SCENARIO: scenarioId
      },
      stdio: "inherit"
    });
    child.on("error", reject);
    child.on("close", (code) => resolve(code ?? 1));
  });
}

function fail(message) {
  console.error(`CodexPill Kite scenario error: ${message}`);
  process.exit(1);
}
