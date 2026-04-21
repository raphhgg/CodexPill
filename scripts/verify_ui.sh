#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPill"
AGENT_NAME="${AGENT_NAME:-local}"
SCENARIO="${SCENARIO:-hosted-menu-default}"
BUILD_ROOT="build"
DERIVED_DATA="${BUILD_ROOT}/DerivedData/${AGENT_NAME}"
RESULT_ROOT="${BUILD_ROOT}/results/${AGENT_NAME}"
RESULT_BUNDLE="${RESULT_ROOT}/${APP_NAME}-verify-ui.xcresult"
ARTIFACT_ROOT="${BUILD_ROOT}/verification/${AGENT_NAME}/${SCENARIO}"
REQUEST_FILE="${BUILD_ROOT}/verification/request.json"

command -v tuist >/dev/null || {
  echo "Tuist is not installed. Install it first."
  exit 1
}

rm -rf "${ARTIFACT_ROOT}" "${RESULT_BUNDLE}"
mkdir -p "${ARTIFACT_ROOT}/screenshots" "${ARTIFACT_ROOT}/logs"

cat > "${REQUEST_FILE}" <<EOF
{
  "artifactDirectory": "${PWD}/${ARTIFACT_ROOT}",
  "scenario": "${SCENARIO}"
}
EOF

cat > "${ARTIFACT_ROOT}/command.txt" <<EOF
AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/verify_ui.sh
EOF

if [[ "${SCENARIO}" != "hosted-menu-default" ]]; then
  case "${SCENARIO}" in
    hosted-menu-busy|hosted-menu-empty|hosted-menu-with-host|hosted-menu-multiple-hosts|hosted-menu-disconnected-host|host-account-missing-on-host)
      ;;
    live-menu-open|live-account-switch|live-remote-host-switch|live-add-host-prompt|live-save-current-prompt|live-sign-in-another-prompt|live-scheduled-refresh)
      ARTIFACT_ROOT="${BUILD_ROOT}/verification/${AGENT_NAME}/${SCENARIO}" \
      ./scripts/live_menubar_smoke.sh
      exit $?
      ;;
    live-status-item-hover)
      ARTIFACT_ROOT="${BUILD_ROOT}/verification/${AGENT_NAME}/${SCENARIO}" \
      ./scripts/live_status_item_hover_smoke.sh
      exit $?
      ;;
    *)
      cat > "${ARTIFACT_ROOT}/summary.json" <<EOF
{
  "artifacts": [],
  "assertions": [],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/verify_ui.sh",
  "gaps": [
    "Unknown scenario '${SCENARIO}'",
    "Try SCENARIO=hosted-menu-default, hosted-menu-busy, hosted-menu-empty, hosted-menu-with-host, hosted-menu-multiple-hosts, hosted-menu-disconnected-host, host-account-missing-on-host, live-menu-open, live-account-switch, live-remote-host-switch, live-add-host-prompt, live-save-current-prompt, live-sign-in-another-prompt, live-scheduled-refresh, or live-status-item-hover"
  ],
  "scenario": "${SCENARIO}",
  "status": "failed"
}
EOF
      echo "Unknown verify-ui scenario: ${SCENARIO}" >&2
      exit 2
      ;;
  esac
fi

TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

xcodebuild test \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  -resultBundlePath "${RESULT_BUNDLE}" \
  -only-testing:"${APP_NAME}Tests/MenuBarUIValidationTests" \
  > "${ARTIFACT_ROOT}/logs/xcodebuild.log" 2>&1

for required in \
  "${ARTIFACT_ROOT}/screenshots/${SCENARIO}.png" \
  "${ARTIFACT_ROOT}/ui-tree.json" \
  "${ARTIFACT_ROOT}/scenario-summary.json"; do
  if [[ ! -f "${required}" ]]; then
    echo "Missing expected UI validation artifact: ${required}" >&2
    exit 3
  fi
done

case "${SCENARIO}" in
  hosted-menu-default)
    ASSERTIONS_JSON='[
    "Current Account section includes the active account summary",
    "Two inactive accounts are visible and one account overflows into More Accounts…",
    "Status message is omitted when the menu is not busy"
  ]'
    ;;
  hosted-menu-busy)
    ASSERTIONS_JSON='[
    "Busy state exposes only the current account plus shared account and preference controls",
    "Busy status message is rendered into the artifact snapshot",
    "Save and sign-in actions are marked disabled in the snapshot"
  ]'
    ;;
  hosted-menu-empty)
    ASSERTIONS_JSON='[
    "Empty state shows no active saved account",
    "Save Current Account remains available when the menu is idle and empty",
    "Remove Account still renders as a stable control even when no saved accounts exist"
  ]'
    ;;
  hosted-menu-with-host)
    ASSERTIONS_JSON='[
    "Remote host state renders in its own section",
    "Accounts continues to reflect the local saved-account catalog",
    "One inactive account still overflows into More Accounts… with a connected host present"
  ]'
    ;;
  hosted-menu-multiple-hosts)
    ASSERTIONS_JSON='[
    "Each connected host renders its own remote-account card",
    "Accounts still reflects only the local saved-account catalog",
    "Overflow account behavior stays intact with multiple connected hosts"
  ]'
    ;;
  hosted-menu-disconnected-host)
    ASSERTIONS_JSON='[
    "Disconnected hosts stay out of the primary Remote Accounts section",
    "Configured hosts remain available under Hosts and per-account switch targets"
  ]'
    ;;
  host-account-missing-on-host)
    ASSERTIONS_JSON='[
    "Missing remote snapshots change the action copy to install-and-switch",
    "Accounts still comes from the local catalog only"
  ]'
    ;;
esac

cat > "${ARTIFACT_ROOT}/summary.json" <<EOF
{
  "artifacts": [
    "screenshots/${SCENARIO}.png",
    "ui-tree.json",
    "scenario-summary.json",
    "logs/xcodebuild.log"
  ],
  "assertions": ${ASSERTIONS_JSON},
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/verify_ui.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "status": "passed"
}
EOF

echo "UI validation artifacts written to ${ARTIFACT_ROOT}"
