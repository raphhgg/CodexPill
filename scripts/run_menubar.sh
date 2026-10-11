#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="Refill"
AGENT_NAME="${AGENT_NAME:-local}"
DERIVED_DATA="build/DerivedData/${AGENT_NAME}"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug/${APP_NAME}.app"
PROJECT_PATH="${APP_NAME}.xcodeproj"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUILD_VERSION="$(date +%Y%m%d%H%M%S)"
BUNDLE_ID_OVERRIDE="${CODEXPILL_BUNDLE_ID:-com.raphhgg.codexpill.dev}"

command -v tuist >/dev/null || {
  echo "Tuist is not installed. Install it first."
  exit 1
}

# Keep the loop shell-first. Generated Xcode artifacts are transient
# build intermediates for xcodebuild, not something we open in Xcode.
"${SCRIPT_DIR}/stop_menubar.sh" >/dev/null 2>&1 || true

TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
xcodebuild_args=(
  build
  -project "${PROJECT_PATH}"
  -scheme "${APP_NAME}"
  -configuration Debug
  -destination "platform=macOS"
  -derivedDataPath "${DERIVED_DATA}"
  CURRENT_PROJECT_VERSION="${BUILD_VERSION}"
)
if [[ -n "${BUNDLE_ID_OVERRIDE}" ]]; then
  xcodebuild_args+=(PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID_OVERRIDE}")
fi
xcodebuild "${xcodebuild_args[@]}"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${APP_PATH}/Contents/Info.plist")"
if [[ -x "${LSREGISTER}" ]]; then
  should_unregister_registered_app() {
    local registered_app="$1"
    [[ -n "${registered_app}" ]] || return 1
    [[ "${registered_app}" != "${APP_PATH}" ]] || return 1
    [[ "${registered_app}" == "${REPO_ROOT}/build/"* ]]
  }

  while IFS= read -r registered_app; do
    registered_app="${registered_app%% (0x*}"
    should_unregister_registered_app "${registered_app}" || continue
    "${LSREGISTER}" -u "${registered_app}" >/dev/null 2>&1 || true
  done < <("${LSREGISTER}" -dump | awk -v bundle_id="${BUNDLE_ID}" '
    /^bundle id:/ {
      path = ""
      matched = 0
    }
    /^path:/ {
      sub(/^path:[[:space:]]*/, "", $0)
      path = $0
    }
    $1 == "identifier:" && $2 == bundle_id {
      matched = 1
    }
    /^--------------------------------------------------------------------------------$/ {
      if (matched && path != "") print path
      path = ""
      matched = 0
    }
  ')

  if command -v mdfind >/dev/null; then
    while IFS= read -r registered_app; do
      should_unregister_registered_app "${registered_app}" || continue
      "${LSREGISTER}" -u "${registered_app}" >/dev/null 2>&1 || true
    done < <(mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}'" || true)
  fi

  # Notification Center resolves sender icons through LaunchServices. Force the
  # freshly built bundle to win over stale debug builds with the same bundle id.
  "${LSREGISTER}" -f "${APP_PATH}" >/dev/null 2>&1 || true
fi

open "${APP_PATH}"
