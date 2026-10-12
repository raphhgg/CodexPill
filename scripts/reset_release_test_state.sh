#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Refill"
# Before the rename the app was CodexPill. Its state is cleaned up too.
LEGACY_APP_NAME="CodexPill"
REPO_DIR="${HOME}/Projects/CodexPill"
BUNDLE_IDS=(
  "com.raphhgg.refill"
  "com.raphhgg.refill.dev"
  "com.raphhgg.refill.demo"
  "com.raphhgg.refill.staging"
  "com.raphhgg.codexpill"
  "com.raphhgg.codexpill.dev"
  "com.raphhgg.codexpill.demo"
  "com.raphhgg.codexpill.staging"
)
REMOTE_HOST=""
APPLY=0
INSTALL=0
REMOTE_SIGN_OUT=0

usage() {
  cat <<'EOF'
Usage:
  scripts/reset_release_test_state.sh [--apply] [--install] [--remote HOST] [--remote-sign-out]

Default mode is a dry run. It prints what would be removed.

Options:
  --apply            Actually remove local Refill dev/build/test state.
  --install          After cleanup, install the release via Homebrew.
  --remote HOST      Also clear Refill's remote cache on HOST.
  --remote-sign-out  With --remote, also remove HOST:~/.codex/auth.json.
                    This signs out Codex on the remote host.
  -h, --help         Show this help.

Examples:
  scripts/reset_release_test_state.sh
  scripts/reset_release_test_state.sh --apply --install
  scripts/reset_release_test_state.sh --apply --install --remote workstation
  scripts/reset_release_test_state.sh --apply --remote workstation --remote-sign-out
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      ;;
    --install)
      INSTALL=1
      ;;
    --remote)
      [[ $# -ge 2 ]] || {
        echo "error: --remote requires a host" >&2
        exit 2
      }
      REMOTE_HOST="$2"
      shift
      ;;
    --remote-sign-out)
      REMOTE_SIGN_OUT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

run() {
  if [[ "${APPLY}" == "1" ]]; then
    "$@"
  else
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  fi
}

run_allow_failure() {
  if [[ "${APPLY}" == "1" ]]; then
    "$@" || true
  else
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  fi
}

remove_path() {
  local path="$1"
  run rm -rf "${path}"
}

remove_glob() {
  local pattern="$1"
  if [[ "${APPLY}" == "1" ]]; then
    find "$(dirname "${pattern}")" -maxdepth 1 -name "$(basename "${pattern}")" -exec rm -rf {} +
  else
    echo "[dry-run] remove matching ${pattern}"
  fi
}

reset_notification_preferences() {
  local notification_dir="${HOME}/Library/Application Support/NotificationCenter"
  local usernoted_db="${HOME}/Library/Group Containers/group.com.apple.usernoted/db2/db"
  local bundle_list="'${BUNDLE_IDS[0]}'"
  local bundle_id
  for bundle_id in "${BUNDLE_IDS[@]:1}"; do
    bundle_list+=", '${bundle_id}'"
  done

  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 not found; skipping macOS notification preference reset."
    return
  fi

  local found=0
  local db
  local candidate_dbs=()
  if [[ -d "${notification_dir}" ]]; then
    candidate_dbs+=("${notification_dir}"/*.db)
  fi
  candidate_dbs+=("${usernoted_db}")

  for db in "${candidate_dbs[@]}"; do
    [[ -e "${db}" ]] || continue
    found=1
    run_allow_failure sqlite3 "${db}" "
      DELETE FROM record
      WHERE app_id IN (
        SELECT app_id FROM app WHERE identifier IN (${bundle_list})
      );
      DELETE FROM app
      WHERE identifier IN (${bundle_list});
    "
  done

  if [[ "${found}" == "0" ]]; then
    echo "No macOS notification databases found; skipping notification preference reset."
    return
  fi

  echo "Restarting macOS notification agents so notification settings reload..."
  run_allow_failure killall usernoted
  run_allow_failure killall NotificationCenter
}

echo "Resetting ${APP_NAME} release-test state."
if [[ "${APPLY}" != "1" ]]; then
  echo "Dry run only. Rerun with --apply to remove files."
fi

echo
echo "Stopping running app..."
run_allow_failure pkill -x "${APP_NAME}"
run_allow_failure pkill -x "${LEGACY_APP_NAME}"

echo
echo "Removing installed apps and local build artifacts..."
for name in "${APP_NAME}" "${LEGACY_APP_NAME}"; do
  remove_path "/Applications/${name}.app"
  remove_path "${HOME}/Applications/${name}.app"
  remove_path "${REPO_DIR}/${name}.xcodeproj"
  remove_path "${REPO_DIR}/${name}.xcworkspace"
done
remove_path "${REPO_DIR}/build"
remove_path "${REPO_DIR}/Derived"

echo
echo "Removing Refill app state and legacy state..."
remove_path "${HOME}/Library/Application Support/${APP_NAME}"
remove_path "${HOME}/Library/Caches/${APP_NAME}"
remove_path "${HOME}/Library/Application Support/${LEGACY_APP_NAME}"
remove_path "${HOME}/Library/Caches/${LEGACY_APP_NAME}"
remove_path "${HOME}/Library/Application Support/CodexSwitchboard"

echo
echo "Removing Refill preferences and validation/demo/test leftovers..."
for bundle_id in "${BUNDLE_IDS[@]}"; do
  remove_path "${HOME}/Library/Preferences/${bundle_id}.plist"
done
remove_path "${HOME}/Library/Preferences/CodexPill.demo.plist"
remove_path "${HOME}/Library/Preferences/CodexPillScreenshotDemo.plist"
remove_glob "${HOME}/Library/Preferences/CodexPill.validation*.plist"
remove_glob "${HOME}/Library/Preferences/CodexPillSettingsStoreTests-*.plist"

echo
echo "Removing Refill macOS notification preferences..."
reset_notification_preferences

echo
echo "Removing isolated temporary Codex homes..."
remove_glob "${TMPDIR:-/tmp}/${APP_NAME}-CODEX_HOME-*"
remove_glob "${TMPDIR:-/tmp}/${LEGACY_APP_NAME}-CODEX_HOME-*"

echo
echo "Removing local Refill crash reports..."
remove_glob "${HOME}/Library/Logs/DiagnosticReports/${APP_NAME}-*.ips"
remove_glob "${HOME}/Library/Logs/DiagnosticReports/${LEGACY_APP_NAME}-*.ips"

if [[ -n "${REMOTE_HOST}" ]]; then
  echo
  echo "Removing remote Refill cache on ${REMOTE_HOST}..."
  run ssh "${REMOTE_HOST}" "rm -rf ~/.codexpill"

  if [[ "${REMOTE_SIGN_OUT}" == "1" ]]; then
    echo "Signing out remote Codex on ${REMOTE_HOST}..."
    run ssh "${REMOTE_HOST}" "rm -f ~/.codex/auth.json"
  fi
fi

if [[ "${INSTALL}" == "1" ]]; then
  echo
  echo "Installing release via Homebrew..."
  run brew tap raphhgg/tap
  run brew install --cask codexpill
fi

echo
if [[ "${APPLY}" == "1" ]]; then
  echo "Release-test reset complete."
else
  echo "Dry run complete. No files were removed."
fi
