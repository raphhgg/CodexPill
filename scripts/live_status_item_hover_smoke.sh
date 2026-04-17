#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPill"
APP_BUNDLE_ID="com.raphhgg.codexpill"
AGENT_NAME="${AGENT_NAME:-local}"
SCENARIO="${SCENARIO:-live-status-item-hover}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-build/verification/${AGENT_NAME}/${SCENARIO}}"
SCREENSHOT_PATH="${ARTIFACT_ROOT}/screenshots/${SCENARIO}.png"
SUMMARY_PATH="${ARTIFACT_ROOT}/summary.json"
COMMAND_PATH="${ARTIFACT_ROOT}/command.txt"
LIVE_SNAPSHOT_PATH="${ARTIFACT_ROOT}/live-menu-snapshot.json"
VALIDATION_EVENTS_PATH="${ARTIFACT_ROOT}/validation-events.jsonl"
RUNTIME_ASSERTIONS_PATH="${ARTIFACT_ROOT}/runtime-assertions.json"
INITIAL_SNAPSHOT_PATH="${ARTIFACT_ROOT}/initial-status-item-snapshot.json"
HOVERED_SNAPSHOT_PATH="${ARTIFACT_ROOT}/hovered-status-item-snapshot.json"
UNHOVERED_SNAPSHOT_PATH="${ARTIFACT_ROOT}/unhovered-status-item-snapshot.json"
RUN_LOG_PATH="${ARTIFACT_ROOT}/logs/run-menubar.log"
PROOF_LAYER="live_ui"
INVARIANT_IDS_JSON='["menubar.text_on_hover.stays_visible_inside_resized_bounds"]'

mkdir -p "${ARTIFACT_ROOT}/screenshots" "${ARTIFACT_ROOT}/logs"

cat > "${COMMAND_PATH}" <<EOF
AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_status_item_hover_smoke.sh
EOF

ORIGINAL_DISPLAY_MODE_FILE="$(mktemp)"
if defaults read "${APP_BUNDLE_ID}" statusBarDisplayMode >"${ORIGINAL_DISPLAY_MODE_FILE}" 2>/dev/null; then
  HAD_ORIGINAL_DISPLAY_MODE=1
else
  HAD_ORIGINAL_DISPLAY_MODE=0
fi

cleanup() {
  if [[ "${HAD_ORIGINAL_DISPLAY_MODE}" == "1" ]]; then
    defaults write "${APP_BUNDLE_ID}" statusBarDisplayMode "$(cat "${ORIGINAL_DISPLAY_MODE_FILE}")" >/dev/null 2>&1 || true
  else
    defaults delete "${APP_BUNDLE_ID}" statusBarDisplayMode >/dev/null 2>&1 || true
  fi
  rm -f "${ORIGINAL_DISPLAY_MODE_FILE}"
  ./scripts/stop_menubar.sh >/dev/null 2>&1 || true
}
trap cleanup EXIT

defaults write "${APP_BUNDLE_ID}" statusBarDisplayMode textOnHover

CODEXPILL_VALIDATION_OUTPUT="${PWD}/${LIVE_SNAPSHOT_PATH}" \
  CODEXPILL_VALIDATION_EVENTS_OUTPUT="${PWD}/${VALIDATION_EVENTS_PATH}" \
  CODEXPILL_VALIDATION_SCENARIO="${SCENARIO}" \
  ./scripts/run_menubar.sh > "${RUN_LOG_PATH}" 2>&1

for _ in $(seq 1 30); do
  [[ -f "${LIVE_SNAPSHOT_PATH}" ]] && break
  sleep 0.2
done

if [[ ! -f "${LIVE_SNAPSHOT_PATH}" ]]; then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "logs/run-menubar.log"
  ],
  "assertions": [],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_status_item_hover_smoke.sh",
  "gaps": [
    "The menubar app did not emit a validation snapshot after launch."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "validation_gap",
  "failureStep": "initial_snapshot_emit"
}
EOF
  exit 7
fi

read_status_item_field() {
  ruby - "${LIVE_SNAPSHOT_PATH}" "$1" <<'RUBY'
require "json"

snapshot_path, field = ARGV
snapshot = JSON.parse(File.read(snapshot_path))
status_item = snapshot["statusItem"] || {}

value =
  case field
  when "hasData"
    snapshot["hasStatusItemContentData"]
  when "mode"
    snapshot["effectiveStatusBarDisplayMode"]
  when "isTitleVisible"
    status_item["isTitleVisible"]
  when "displayedTitle"
    status_item["displayedTitle"]
  when "x"
    status_item.dig("buttonFrame", "x")
  when "y"
    status_item.dig("buttonFrame", "y")
  when "width"
    status_item.dig("buttonFrame", "width")
  when "height"
    status_item.dig("buttonFrame", "height")
  when "isHovered"
    status_item["isHovered"]
  when "isPointerInsideButton"
    status_item["isPointerInsideButton"]
  when "pointerX"
    status_item.dig("pointerLocation", "x")
  when "pointerY"
    status_item.dig("pointerLocation", "y")
  else
    nil
  end

puts(value.nil? ? "" : value)
RUBY
}

read_hover_event_proof() {
  ruby - "${VALIDATION_EVENTS_PATH}" <<'RUBY'
require "json"

events_path = ARGV.fetch(0)
required = [
  "status_item_hover_entered",
  "status_item_title_became_visible",
  "status_item_hover_exit_scheduled",
  "status_item_hover_exited",
  "status_item_title_hidden"
]

events = if File.exist?(events_path)
  File.readlines(events_path, chomp: true).map do |line|
    next if line.strip.empty?
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end.compact
else
  []
end

cursor = 0
proof_sequence = []

required.each do |required_event|
  matched = false
  while cursor < events.length
    if events[cursor]["event"] == required_event
      proof_sequence << required_event
      cursor += 1
      matched = true
      break
    end
    cursor += 1
  end
  break unless matched
end

puts JSON.generate(
  {
    "passed" => proof_sequence == required,
    "requiredSequence" => required,
    "proofSequence" => proof_sequence,
    "eventCount" => events.length,
    "eventsPathPresent" => File.exist?(events_path)
  }
)
RUBY
}

wait_for_usable_status_item_frame() {
  for _ in $(seq 1 40); do
    local x y width height
    x="$(read_status_item_field x)"
    y="$(read_status_item_field y)"
    width="$(read_status_item_field width)"
    height="$(read_status_item_field height)"
    if ruby -e 'x = ARGV[0].to_f; y = ARGV[1].to_f; width = ARGV[2].to_f; height = ARGV[3].to_f; exit((width > 0 && height > 0 && !(x == 0 && y <= 0)) ? 0 : 1)' "${x:-0}" "${y:-0}" "${width:-0}" "${height:-0}"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

FRAME_READY="false"
if wait_for_usable_status_item_frame; then
  FRAME_READY="true"
fi

HAS_DATA="$(read_status_item_field hasData)"
MODE="$(read_status_item_field mode)"
X="$(read_status_item_field x)"
Y="$(read_status_item_field y)"
WIDTH="$(read_status_item_field width)"
HEIGHT="$(read_status_item_field height)"
INITIAL_VISIBLE="$(read_status_item_field isTitleVisible)"

cp "${LIVE_SNAPSHOT_PATH}" "${INITIAL_SNAPSHOT_PATH}"

if [[ "${HAS_DATA}" != "true" || "${MODE}" != "textOnHover" || -z "${X}" || -z "${Y}" || -z "${WIDTH}" || -z "${HEIGHT}" || "${FRAME_READY}" != "true" ]]; then
  cat > "${RUNTIME_ASSERTIONS_PATH}" <<EOF
[
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe preconditions are satisfied",
    "passed": false,
    "actual": {
      "hasStatusItemContentData": ${HAS_DATA:-null},
      "effectiveStatusBarDisplayMode": "${MODE}",
      "frameReady": ${FRAME_READY},
      "buttonFrame": {
        "x": ${X:-null},
        "y": ${Y:-null},
        "width": ${WIDTH:-null},
        "height": ${HEIGHT:-null}
      }
    }
  }
]
EOF
  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-menu-snapshot.json",
    "validation-events.jsonl",
    "initial-status-item-snapshot.json",
    "runtime-assertions.json",
    "logs/run-menubar.log"
  ],
  "assertions": [],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_status_item_hover_smoke.sh",
  "gaps": [
    "The hover probe could not establish text-on-hover preconditions.",
    "The active account needs live status-item data and the probe needs a status-item frame in the validation snapshot."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "validation_gap",
  "failureStep": "preconditions"
}
EOF
  exit 8
fi

HOVER_X="$(ruby -e "puts((ARGV[0].to_f + (ARGV[2].to_f / 2.0)).round(1))" "${X}" "${Y}" "${WIDTH}")"
HOVER_Y="$(ruby -e "puts((ARGV[1].to_f + (ARGV[3].to_f / 2.0)).round(1))" "${X}" "${Y}" "${WIDTH}" "${HEIGHT}")"
UNHOVER_X="$(ruby -e "puts((ARGV[0].to_f + ARGV[2].to_f + 120.0).round(1))" "${X}" "${Y}" "${WIDTH}")"
UNHOVER_Y="${HOVER_Y}"

move_mouse() {
  /usr/bin/swift -e '
import AppKit
import CoreGraphics

let appKitX = Double(CommandLine.arguments[1])!
let appKitY = Double(CommandLine.arguments[2])!
let appKitPoint = NSPoint(x: appKitX, y: appKitY)

let targetPoint: CGPoint
if let screen = NSScreen.screens.first(where: { NSMouseInRect(appKitPoint, $0.frame, false) }) {
    let frame = screen.frame
    targetPoint = CGPoint(x: appKitPoint.x, y: frame.maxY - appKitPoint.y)
} else {
    targetPoint = CGPoint(x: appKitPoint.x, y: appKitPoint.y)
}

CGWarpMouseCursorPosition(targetPoint)
let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: targetPoint, mouseButton: .left)
moveEvent?.post(tap: .cghidEventTap)
' "$1" "$2" >/dev/null
}

hover_pointer_reached="false"
hover_pointer_state='{}'
for _ in $(seq 1 4); do
  move_mouse "${HOVER_X}" "${HOVER_Y}"
  for _ in $(seq 1 10); do
    sleep 0.1
    POINTER_INSIDE="$(read_status_item_field isPointerInsideButton)"
    POINTER_X="$(read_status_item_field pointerX)"
    POINTER_Y="$(read_status_item_field pointerY)"
    HOVER_STATE="$(read_status_item_field isHovered)"
    hover_pointer_state="$(cat <<EOF
{
  "target": { "x": ${HOVER_X}, "y": ${HOVER_Y} },
  "pointerLocation": { "x": ${POINTER_X:-null}, "y": ${POINTER_Y:-null} },
  "isPointerInsideButton": ${POINTER_INSIDE:-false},
  "isHovered": ${HOVER_STATE:-false}
}
EOF
)"
    if [[ "${POINTER_INSIDE}" == "true" ]]; then
      hover_pointer_reached="true"
      break 2
    fi
  done
done

if [[ "${hover_pointer_reached}" != "true" ]]; then
  cp "${LIVE_SNAPSHOT_PATH}" "${HOVERED_SNAPSHOT_PATH}"
  screencapture -x "${SCREENSHOT_PATH}"
  cat > "${RUNTIME_ASSERTIONS_PATH}" <<EOF
[
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe preconditions are satisfied",
    "passed": true,
    "actual": {
      "hasStatusItemContentData": ${HAS_DATA},
      "effectiveStatusBarDisplayMode": "${MODE}",
      "initialTitleVisible": ${INITIAL_VISIBLE}
    }
  },
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe moved the pointer into the live status item bounds",
    "passed": false,
    "actual": ${hover_pointer_state}
  }
]
EOF
  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-menu-snapshot.json",
    "validation-events.jsonl",
    "initial-status-item-snapshot.json",
    "hovered-status-item-snapshot.json",
    "runtime-assertions.json",
    "screenshots/${SCENARIO}.png",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The probe forced text-on-hover mode through persisted settings"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_status_item_hover_smoke.sh",
  "gaps": [
    "The hover probe could not move the pointer into the live status item bounds.",
    "This is a live-QA environment block, so the probe could not validate hover behavior."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "pointer_move_to_status_item"
}
EOF
  exit 9
fi

HOVER_VISIBLE="false"
for _ in $(seq 1 20); do
  sleep 0.1
  HOVER_VISIBLE="$(read_status_item_field isTitleVisible)"
  HOVER_TITLE="$(read_status_item_field displayedTitle)"
  if [[ "${HOVER_VISIBLE}" == "true" && -n "${HOVER_TITLE}" ]]; then
    break
  fi
done

cp "${LIVE_SNAPSHOT_PATH}" "${HOVERED_SNAPSHOT_PATH}"
screencapture -x "${SCREENSHOT_PATH}"

unhover_pointer_reached="false"
unhover_pointer_state='{}'
for _ in $(seq 1 4); do
  move_mouse "${UNHOVER_X}" "${UNHOVER_Y}"
  for _ in $(seq 1 10); do
    sleep 0.1
    POINTER_INSIDE="$(read_status_item_field isPointerInsideButton)"
    POINTER_X="$(read_status_item_field pointerX)"
    POINTER_Y="$(read_status_item_field pointerY)"
    HOVER_STATE="$(read_status_item_field isHovered)"
    unhover_pointer_state="$(cat <<EOF
{
  "target": { "x": ${UNHOVER_X}, "y": ${UNHOVER_Y} },
  "pointerLocation": { "x": ${POINTER_X:-null}, "y": ${POINTER_Y:-null} },
  "isPointerInsideButton": ${POINTER_INSIDE:-false},
  "isHovered": ${HOVER_STATE:-false}
}
EOF
)"
    if [[ "${POINTER_INSIDE}" == "false" ]]; then
      unhover_pointer_reached="true"
      break 2
    fi
  done
done

if [[ "${unhover_pointer_reached}" != "true" ]]; then
  cp "${LIVE_SNAPSHOT_PATH}" "${UNHOVERED_SNAPSHOT_PATH}"
  cat > "${RUNTIME_ASSERTIONS_PATH}" <<EOF
[
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe preconditions are satisfied",
    "passed": true,
    "actual": {
      "hasStatusItemContentData": ${HAS_DATA},
      "effectiveStatusBarDisplayMode": "${MODE}",
      "initialTitleVisible": ${INITIAL_VISIBLE}
    }
  },
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe moved the pointer into the live status item bounds",
    "passed": true,
    "actual": ${hover_pointer_state}
  },
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe moved the pointer back out of the live status item bounds",
    "passed": false,
    "actual": ${unhover_pointer_state}
  }
]
EOF
  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-menu-snapshot.json",
    "validation-events.jsonl",
    "initial-status-item-snapshot.json",
    "hovered-status-item-snapshot.json",
    "unhovered-status-item-snapshot.json",
    "runtime-assertions.json",
    "screenshots/${SCENARIO}.png",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The probe forced text-on-hover mode through persisted settings"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_status_item_hover_smoke.sh",
  "gaps": [
    "The hover probe could not move the pointer back out of the live status item bounds.",
    "This is a live-QA environment block, so the probe could not validate hover teardown."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "pointer_move_off_status_item"
}
EOF
  exit 10
fi

UNHOVER_VISIBLE="true"
for _ in $(seq 1 20); do
  sleep 0.1
  UNHOVER_VISIBLE="$(read_status_item_field isTitleVisible)"
  if [[ "${UNHOVER_VISIBLE}" == "false" ]]; then
    break
  fi
done

cp "${LIVE_SNAPSHOT_PATH}" "${UNHOVERED_SNAPSHOT_PATH}"
EVENT_PROOF_JSON="$(read_hover_event_proof)"
EVENT_PROOF_PASSED="$(printf '%s' "${EVENT_PROOF_JSON}" | ruby -rjson -e 'print JSON.parse(STDIN.read)["passed"]')"
EVENT_PROOF_SEQUENCE="$(printf '%s' "${EVENT_PROOF_JSON}" | ruby -rjson -e 'print JSON.generate(JSON.parse(STDIN.read)["proofSequence"])')"

cat > "${RUNTIME_ASSERTIONS_PATH}" <<EOF
[
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe preconditions are satisfied",
    "passed": true,
    "actual": {
      "hasStatusItemContentData": ${HAS_DATA},
      "effectiveStatusBarDisplayMode": "${MODE}",
      "initialTitleVisible": ${INITIAL_VISIBLE}
    }
  },
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe moved the pointer into the live status item bounds",
    "passed": true,
    "actual": ${hover_pointer_state}
  },
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Hovering the live status item reveals the text-on-hover title",
    "passed": ${HOVER_VISIBLE},
    "actual": $(cat "${HOVERED_SNAPSHOT_PATH}")
  },
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Probe moved the pointer back out of the live status item bounds",
    "passed": true,
    "actual": ${unhover_pointer_state}
  },
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Moving away hides the text-on-hover title again",
    "passed": $( [[ "${UNHOVER_VISIBLE}" == "false" ]] && echo true || echo false ),
    "actual": $(cat "${UNHOVERED_SNAPSHOT_PATH}")
  },
  {
    "invariantIds": ${INVARIANT_IDS_JSON},
    "proofLayer": "${PROOF_LAYER}",
    "name": "Validation events prove the hover lifecycle",
    "passed": ${EVENT_PROOF_PASSED},
    "actual": ${EVENT_PROOF_JSON}
  }
]
EOF

if [[ "${HOVER_VISIBLE}" != "true" || "${UNHOVER_VISIBLE}" != "false" || "${EVENT_PROOF_PASSED}" != "true" ]]; then
  if [[ "${HOVER_VISIBLE}" != "true" || "${UNHOVER_VISIBLE}" != "false" ]]; then
    FAILURE_TYPE="product_regression"
    FAILURE_STEP="hover_visibility_transition"
    FAILURE_GAP="The live status item did not keep the hover title visible while the pointer was on the status item."
  else
    FAILURE_TYPE="validation_gap"
    FAILURE_STEP="event_sequence_validation"
    FAILURE_GAP="The app did not emit the expected hover lifecycle validation events."
  fi
  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-menu-snapshot.json",
    "validation-events.jsonl",
    "initial-status-item-snapshot.json",
    "hovered-status-item-snapshot.json",
    "unhovered-status-item-snapshot.json",
    "runtime-assertions.json",
    "screenshots/${SCENARIO}.png",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The probe forced text-on-hover mode through persisted settings"
  ],
  "proofSequence": ${EVENT_PROOF_SEQUENCE},
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_status_item_hover_smoke.sh",
  "gaps": [
    "${FAILURE_GAP}"
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "${FAILURE_TYPE}",
  "failureStep": "${FAILURE_STEP}"
}
EOF
  exit 9
fi

cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-menu-snapshot.json",
    "validation-events.jsonl",
    "initial-status-item-snapshot.json",
    "hovered-status-item-snapshot.json",
    "unhovered-status-item-snapshot.json",
    "runtime-assertions.json",
    "screenshots/${SCENARIO}.png",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The probe forced text-on-hover mode through persisted settings",
    "The probe moved the pointer into the live status item bounds",
    "Hovering the live status item revealed the text-on-hover title",
    "The probe moved the pointer back out of the live status item bounds",
    "Moving away hid the text-on-hover title again",
    "Validation events proved the hover lifecycle"
  ],
  "proofSequence": ${EVENT_PROOF_SEQUENCE},
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_status_item_hover_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "status": "passed",
  "failureClass": null,
  "failureStep": null
}
EOF
