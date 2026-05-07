#!/usr/bin/env bash
set -euo pipefail

SCENARIO=""
PROOF_OUTPUT=""
ARTIFACT_ROOT=""

usage() {
  cat >&2 <<'USAGE'
Usage: seal_run_adapter.sh --scenario <scenario-id> --proof-output <path> --artifact-root <path>

Supported scenarios:
  switch-account-changes-active-account
  add-host-destination-validation-failed
  remote-host-refresh-failure-preserves-fallback-state
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      SCENARIO="$2"
      shift 2
      ;;
    --proof-output)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      PROOF_OUTPUT="$2"
      shift 2
      ;;
    --artifact-root)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      ARTIFACT_ROOT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ -z "${SCENARIO}" || -z "${PROOF_OUTPUT}" || -z "${ARTIFACT_ROOT}" ]]; then
  usage
  exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ADAPTER_DIR="${ARTIFACT_ROOT}/adapter"
LOG_PATH="${ADAPTER_DIR}/codexpill-adapter.log"
SCENARIO_METADATA_PATH="${ADAPTER_DIR}/codexpill-scenario.json"

mkdir -p "${ADAPTER_DIR}" "${PROOF_OUTPUT}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s %s\n' "$(timestamp)" "$*" >>"${LOG_PATH}"
}

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.stdin.read())[1:-1])'
}

case "${SCENARIO}" in
  switch-account-changes-active-account)
    CODEXPILL_ENTRYPOINT="make emit-account-switch-proof"
    ;;
  add-host-destination-validation-failed)
    CODEXPILL_ENTRYPOINT="make emit-add-host-validation-failure-proof"
    ;;
  remote-host-refresh-failure-preserves-fallback-state)
    CODEXPILL_ENTRYPOINT="make emit-remote-host-refresh-failure-proof"
    ;;
  *)
    log "unsupported scenario: ${SCENARIO}"
    cat >"${SCENARIO_METADATA_PATH}" <<JSON
{
  "scenario": "$(printf '%s' "${SCENARIO}" | json_escape)",
  "status": "unsupported",
  "supportedScenarios": ["switch-account-changes-active-account", "add-host-destination-validation-failed", "remote-host-refresh-failure-preserves-fallback-state"]
}
JSON
    echo "Unsupported CodexPill Seal runner scenario: ${SCENARIO}" >&2
    exit 64
    ;;
esac

cat >"${SCENARIO_METADATA_PATH}" <<JSON
{
  "scenario": "$(printf '%s' "${SCENARIO}" | json_escape)",
  "status": "started",
  "proofOutput": "$(printf '%s' "${PROOF_OUTPUT}" | json_escape)",
  "artifactRoot": "$(printf '%s' "${ARTIFACT_ROOT}" | json_escape)",
  "codexPillEntrypoint": "$(printf '%s' "${CODEXPILL_ENTRYPOINT}" | json_escape)"
}
JSON

log "starting CodexPill Seal adapter"
log "scenario=${SCENARIO}"
log "proof_output=${PROOF_OUTPUT}"
log "artifact_root=${ARTIFACT_ROOT}"

(
  cd "${REPO_ROOT}"
  OUTPUT_DIR="${PROOF_OUTPUT}" ${CODEXPILL_ENTRYPOINT}
)

cat >"${SCENARIO_METADATA_PATH}" <<JSON
{
  "scenario": "$(printf '%s' "${SCENARIO}" | json_escape)",
  "status": "completed",
  "proofOutput": "$(printf '%s' "${PROOF_OUTPUT}" | json_escape)",
  "artifactRoot": "$(printf '%s' "${ARTIFACT_ROOT}" | json_escape)",
  "codexPillEntrypoint": "$(printf '%s' "${CODEXPILL_ENTRYPOINT}" | json_escape)"
}
JSON

log "completed CodexPill Seal adapter"
