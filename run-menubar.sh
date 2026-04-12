#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPill"
AGENT_NAME="${AGENT_NAME:-local}"
DERIVED_DATA="build/DerivedData/${AGENT_NAME}"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug/${APP_NAME}.app"
PROJECT_PATH="${APP_NAME}.xcodeproj"

command -v tuist >/dev/null || {
  echo "Tuist is not installed. Install it first."
  exit 1
}

# Keep the loop shell-first. Generated Xcode artifacts are transient
# build intermediates for xcodebuild, not something we open in Xcode.
./stop-menubar.sh >/dev/null 2>&1 || true

TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
xcodebuild build \
  -project "${PROJECT_PATH}" \
  -scheme "${APP_NAME}" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}"

open "${APP_PATH}"
