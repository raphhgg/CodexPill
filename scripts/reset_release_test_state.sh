#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPill"
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
  --apply            Actually remove local CodexPill dev/build/test state.
  --install          After cleanup, install the release via Homebrew.
  --remote HOST      Also clear CodexPill's remote cache on HOST.
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

echo "Resetting ${APP_NAME} release-test state."
if [[ "${APPLY}" != "1" ]]; then
  echo "Dry run only. Rerun with --apply to remove files."
fi

echo
echo "Stopping running app..."
run_allow_failure pkill -x "${APP_NAME}"

echo
echo "Removing installed apps and local build artifacts..."
remove_path "/Applications/${APP_NAME}.app"
remove_path "${HOME}/Applications/${APP_NAME}.app"
remove_path "${HOME}/Projects/${APP_NAME}/build"
remove_path "${HOME}/Projects/${APP_NAME}/${APP_NAME}.xcodeproj"
remove_path "${HOME}/Projects/${APP_NAME}/${APP_NAME}.xcworkspace"
remove_path "${HOME}/Projects/${APP_NAME}/Derived"

echo
echo "Removing CodexPill app state and legacy state..."
remove_path "${HOME}/Library/Application Support/CodexPill"
remove_path "${HOME}/Library/Application Support/CodexSwitchboard"

echo
echo "Removing CodexPill preferences and validation/demo/test leftovers..."
remove_path "${HOME}/Library/Preferences/com.raphhgg.codexpill.plist"
remove_path "${HOME}/Library/Preferences/com.raphhgg.codexpill.dev.plist"
remove_path "${HOME}/Library/Preferences/com.raphhgg.codexpill.demo.plist"
remove_path "${HOME}/Library/Preferences/com.raphhgg.codexpill.staging.plist"
remove_path "${HOME}/Library/Preferences/CodexPill.demo.plist"
remove_path "${HOME}/Library/Preferences/CodexPillScreenshotDemo.plist"
remove_glob "${HOME}/Library/Preferences/CodexPill.validation*.plist"
remove_glob "${HOME}/Library/Preferences/CodexPillSettingsStoreTests-*.plist"

echo
echo "Removing isolated temporary Codex homes..."
remove_glob "${TMPDIR:-/tmp}/CodexPill-CODEX_HOME-*"

echo
echo "Removing local CodexPill crash reports..."
remove_glob "${HOME}/Library/Logs/DiagnosticReports/CodexPill-*.ips"

if [[ -n "${REMOTE_HOST}" ]]; then
  echo
  echo "Removing remote CodexPill cache on ${REMOTE_HOST}..."
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
