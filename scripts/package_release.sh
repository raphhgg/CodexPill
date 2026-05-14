#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPill"
PROJECT_PATH="${APP_NAME}.xcodeproj"
SCHEME="${APP_NAME}"
CONFIGURATION="Release"
AGENT_NAME="${AGENT_NAME:-local}"
BUILD_ROOT="${BUILD_ROOT:-build}"
DERIVED_DATA="${DERIVED_DATA:-${BUILD_ROOT}/DerivedData/${AGENT_NAME}-release}"
ARCHIVE_ROOT="${ARCHIVE_ROOT:-${BUILD_ROOT}/release}"
PRODUCTS_DIR="${DERIVED_DATA}/Build/Products/${CONFIGURATION}"
BUILT_APP="${PRODUCTS_DIR}/${APP_NAME}.app"
PACKAGE_DIR="${ARCHIVE_ROOT}/package"
SIGNED_APP="${PACKAGE_DIR}/${APP_NAME}.app"
ARTIFACTS_DIR="${ARCHIVE_ROOT}/artifacts"
NOTARY_DIR="${ARCHIVE_ROOT}/notary"

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
RELEASE_VERSION="${RELEASE_VERSION:-}"
PACKAGE_RELEASE_ALLOW_UNSIGNED="${PACKAGE_RELEASE_ALLOW_UNSIGNED:-0}"
PACKAGE_RELEASE_ALLOW_DIRTY="${PACKAGE_RELEASE_ALLOW_DIRTY:-0}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' was not found."
}

require_clean_tree() {
  if [[ -n "$(git status --porcelain)" && "${PACKAGE_RELEASE_ALLOW_DIRTY}" != "1" ]]; then
    fail "Working tree is dirty. Commit/stash changes or rerun only for local validation with PACKAGE_RELEASE_ALLOW_DIRTY=1."
  fi
}

require_signing_configuration() {
  local missing=()

  [[ -n "${DEVELOPER_ID_APPLICATION}" ]] || missing+=("DEVELOPER_ID_APPLICATION")
  [[ -n "${APPLE_TEAM_ID}" ]] || missing+=("APPLE_TEAM_ID")
  [[ -n "${NOTARY_PROFILE}" ]] || missing+=("NOTARY_PROFILE")

  if (( ${#missing[@]} > 0 )); then
    cat >&2 <<'GUIDANCE'
error: Release signing/notarization is not configured.

Set the missing environment variables without committing or printing their values:
  DEVELOPER_ID_APPLICATION  Developer ID Application signing identity name or SHA-1 hash
  APPLE_TEAM_ID             Apple Developer team ID
  NOTARY_PROFILE            notarytool keychain profile name

Create the notary profile locally with:
  xcrun notarytool store-credentials <profile-name>

For build/zip validation only, rerun with PACKAGE_RELEASE_ALLOW_UNSIGNED=1.
Unsigned artifacts are named UNSIGNED-LOCAL and are not public beta release artifacts.
GUIDANCE
    printf 'Missing: %s\n' "${missing[*]}" >&2
    exit 2
  fi
}

verify_identity_exists() {
  security find-identity -v -p codesigning | grep -Fq "${DEVELOPER_ID_APPLICATION}" \
    || fail "Developer ID signing identity was not found in the keychain."
}

build_release_app() {
  info "Generating Xcode project..."
  TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

  info "Building ${APP_NAME}.app (${CONFIGURATION})..."
  xcodebuild build \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "platform=macOS" \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY=""

  [[ -d "${BUILT_APP}" ]] || fail "Release build did not produce ${BUILT_APP}."
}

prepare_package_app() {
  rm -rf "${PACKAGE_DIR}" "${ARTIFACTS_DIR}" "${NOTARY_DIR}"
  mkdir -p "${PACKAGE_DIR}" "${ARTIFACTS_DIR}" "${NOTARY_DIR}"
  cp -R "${BUILT_APP}" "${SIGNED_APP}"
  find "${SIGNED_APP}" -name '._*' -delete

  if [[ -n "${RELEASE_VERSION}" ]]; then
    local display_version="${RELEASE_VERSION#v}"
    local info_plist="${SIGNED_APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Delete :CodexPillReleaseVersion" "${info_plist}" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :CodexPillReleaseVersion string ${display_version}" "${info_plist}"
  fi
}

sign_notarize_and_verify() {
  info "Signing app with Developer ID and hardened runtime..."
  local sign_attempt
  for sign_attempt in 1 2 3; do
    if codesign --force --deep --timestamp --options runtime \
      --sign "${DEVELOPER_ID_APPLICATION}" \
      "${SIGNED_APP}"; then
      break
    fi

    if [[ "${sign_attempt}" == "3" ]]; then
      fail "Developer ID signing failed after ${sign_attempt} attempts."
    fi

    info "Signing failed, retrying in 5 seconds..."
    sleep 5
  done

  info "Verifying code signature..."
  codesign --verify --deep --strict --verbose=2 "${SIGNED_APP}"
  local signature_details
  signature_details="$(codesign --display --verbose=4 "${SIGNED_APP}" 2>&1)"
  if ! grep -q "flags=.*runtime" <<<"${signature_details}"; then
    printf '%s\n' "${signature_details}" >&2
    fail "Signed app does not report hardened runtime."
  fi

  local notary_zip="${NOTARY_DIR}/${APP_NAME}-notary.zip"
  info "Creating notarization upload..."
  (cd "${PACKAGE_DIR}" && ditto -c -k --keepParent "${APP_NAME}.app" "../notary/$(basename "${notary_zip}")")

  info "Submitting app zip for notarization..."
  xcrun notarytool submit "${notary_zip}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --team-id "${APPLE_TEAM_ID}" \
    --wait

  info "Stapling notarization ticket..."
  xcrun stapler staple "${SIGNED_APP}"
  xcrun stapler validate "${SIGNED_APP}"

  info "Verifying stapled code signature..."
  codesign --verify --deep --strict --verbose=2 "${SIGNED_APP}"

  info "Assessing app with Gatekeeper..."
  spctl --assess --type execute --verbose=4 "${SIGNED_APP}"
}

create_zip() {
  local git_sha
  local dirty_suffix=""
  local unsigned_suffix=""
  git_sha="$(git rev-parse --short HEAD)"

  if [[ -n "$(git status --porcelain)" ]]; then
    dirty_suffix="-DIRTY"
  fi

  if [[ "${PACKAGE_RELEASE_ALLOW_UNSIGNED}" == "1" ]]; then
    unsigned_suffix="-UNSIGNED-LOCAL"
  fi

  local artifact_version="${RELEASE_VERSION:-${git_sha}}"
  local zip_path="${ARTIFACTS_DIR}/${APP_NAME}-${artifact_version}${dirty_suffix}${unsigned_suffix}.zip"

  info "Creating zip artifact..."
  (cd "${PACKAGE_DIR}" && ditto -c -k --keepParent "${APP_NAME}.app" "../artifacts/$(basename "${zip_path}")")

  info "Created ${zip_path}"
}

main() {
  require_command git
  require_command tuist
  require_command xcodebuild
  require_command ditto
  require_command codesign
  require_command xcrun
  require_command spctl
  require_command security
  require_clean_tree

  if [[ "${PACKAGE_RELEASE_ALLOW_UNSIGNED}" != "1" ]]; then
    require_signing_configuration
    verify_identity_exists
  fi

  build_release_app
  prepare_package_app

  if [[ "${PACKAGE_RELEASE_ALLOW_UNSIGNED}" == "1" ]]; then
    info "Skipping signing, notarization, stapling, and Gatekeeper assessment for unsigned local validation."
  else
    sign_notarize_and_verify
  fi

  create_zip
}

main "$@"
