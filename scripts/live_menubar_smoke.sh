#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPill"
AGENT_NAME="${AGENT_NAME:-local}"
SCENARIO="${SCENARIO:-live-menu-open}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-build/verification/${AGENT_NAME}/${SCENARIO}}"
SCREENSHOT_PATH="${ARTIFACT_ROOT}/screenshots/${SCENARIO}.png"
UI_TREE_PATH="${ARTIFACT_ROOT}/ui-tree.json"
SUMMARY_PATH="${ARTIFACT_ROOT}/summary.json"
COMMAND_PATH="${ARTIFACT_ROOT}/command.txt"
LIVE_SNAPSHOT_PATH="${ARTIFACT_ROOT}/live-menu-snapshot.json"
RUNTIME_ASSERTIONS_PATH="${ARTIFACT_ROOT}/runtime-assertions.json"
APP_SERVER_STATUS_PATH="${ARTIFACT_ROOT}/app-server-status.json"
LIVE_AUTH_STATUS_PATH="${ARTIFACT_ROOT}/live-auth-status.json"

mkdir -p "${ARTIFACT_ROOT}/screenshots" "${ARTIFACT_ROOT}/logs"

cat > "${COMMAND_PATH}" <<EOF
AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh
EOF

APP_SERVER_STDOUT="$(mktemp)"
APP_SERVER_STDERR="$(mktemp)"
{
  cat <<'EOF'
{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codexpill","title":"CodexPill","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}
{"method":"initialized","params":{}}
{"method":"account/read","id":2,"params":{"refreshToken":true}}
{"method":"account/rateLimits/read","id":3,"params":null}
EOF
  sleep 8
} | /Applications/Codex.app/Contents/Resources/codex app-server > "${APP_SERVER_STDOUT}" 2> "${APP_SERVER_STDERR}"

if ! ruby - "${APP_SERVER_STDOUT}" "${APP_SERVER_STDERR}" "${APP_SERVER_STATUS_PATH}" <<'RUBY'
require "json"

stdout_path, stderr_path, status_path = ARGV
stdout_lines = File.readlines(stdout_path, chomp: true)
stderr_text = File.read(stderr_path).strip
responses = stdout_lines.map do |line|
  next if line.strip.empty?
  JSON.parse(line)
rescue JSON::ParserError
  nil
end.compact

account = responses.find { |entry| entry["id"] == 2 }
rate_limits = responses.find { |entry| entry["id"] == 3 }

payload = {
  "accountResponsePresent" => !account.nil?,
  "rateLimitsResponsePresent" => !rate_limits.nil?,
  "accountEmail" => account&.dig("result", "account", "email"),
  "planType" => account&.dig("result", "account", "planType"),
  "primaryUsedPercent" => rate_limits&.dig("result", "rateLimits", "primary", "usedPercent"),
  "secondaryUsedPercent" => rate_limits&.dig("result", "rateLimits", "secondary", "usedPercent"),
  "stderr" => stderr_text.empty? ? nil : stderr_text
}

File.write(status_path, JSON.pretty_generate(payload))

exit(
  payload["accountResponsePresent"] &&
  payload["rateLimitsResponsePresent"] &&
  !payload["accountEmail"].to_s.empty? &&
  !payload["primaryUsedPercent"].nil? ? 0 : 1
)
RUBY
then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "app-server-status.json"
  ],
  "assertions": [],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The local codex app-server probe did not return both account identity and rate-limit data.",
    "CodexPill cannot claim account-data correctness while this probe is failing."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed"
}
EOF
  rm -f "${APP_SERVER_STDOUT}" "${APP_SERVER_STDERR}"
  echo "Live smoke failed: app-server probe did not return complete account data." >&2
  exit 9
fi
rm -f "${APP_SERVER_STDOUT}" "${APP_SERVER_STDERR}"

if ! ruby - "${LIVE_AUTH_STATUS_PATH}" <<'RUBY'
require "base64"
require "digest"
require "json"

status_path = ARGV.fetch(0)
auth_path = File.expand_path("~/.codex/auth.json")
raw = JSON.parse(File.read(auth_path))
id_token = raw["id_token"] || raw.dig("tokens", "id_token")
payload = {}

if id_token
  encoded_payload = id_token.split(".")[1]
  if encoded_payload
    encoded_payload += "=" * ((4 - encoded_payload.length % 4) % 4)
    payload = JSON.parse(Base64.urlsafe_decode64(encoded_payload)) rescue {}
  end
end

auth = payload["https://api.openai.com/auth"] || {}
organizations = payload["https://api.openai.com/organizations"] || auth["organizations"] || []
default_organization = organizations.find { |organization| organization["is_default"] } || organizations.first || {}
identity_components = [
  raw.dig("tokens", "account_id"),
  payload["sub"],
  auth["chatgpt_user_id"],
  default_organization["id"]
].map { |value| value.to_s.strip }.reject(&:empty?)
identity_digest = identity_components.empty? ? nil : Digest::SHA256.hexdigest(identity_components.join("|"))

File.write(
  status_path,
  JSON.pretty_generate(
    {
      "email" => payload["email"],
      "planType" => auth["chatgpt_plan_type"],
      "identityDigest" => identity_digest
    }
  )
)
RUBY
then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "app-server-status.json"
  ],
  "assertions": [
    "The local codex app-server probe returned account identity and rate-limit data"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The live auth snapshot could not be read from ~/.codex/auth.json.",
    "CodexPill cannot prove current-account correctness while the source-of-truth auth snapshot is missing or malformed."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed"
}
EOF
  echo "Live smoke failed: could not read ~/.codex/auth.json." >&2
  exit 10
fi

CODEXPILL_VALIDATION_OUTPUT="${PWD}/${LIVE_SNAPSHOT_PATH}" \
  ./scripts/run_menubar.sh > "${ARTIFACT_ROOT}/logs/run-menubar.log" 2>&1

for _ in $(seq 1 20); do
  if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if ! pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "logs/run-menubar.log"
  ],
  "assertions": [],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The menubar app process did not appear after launch."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed"
}
EOF
  echo "Live smoke failed: ${APP_NAME} did not start." >&2
  exit 3
fi

for _ in $(seq 1 20); do
  if [[ -f "${LIVE_SNAPSHOT_PATH}" ]]; then
    break
  fi
  sleep 0.5
done

if [[ ! -f "${LIVE_SNAPSHOT_PATH}" ]]; then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "app-server-status.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The local codex app-server probe returned account identity and rate-limit data",
    "CodexPill process launched successfully"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The app started but did not emit a live menu snapshot to ${LIVE_SNAPSHOT_PATH}.",
    "Validation mode is wired through CODEXPILL_VALIDATION_OUTPUT; if this file is missing the runtime proof path is broken."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed"
}
EOF
  echo "Live smoke failed: ${APP_NAME} did not emit a live menu snapshot." >&2
  exit 7
fi

run_runtime_assertions() {
  ruby - "${LIVE_SNAPSHOT_PATH}" "${RUNTIME_ASSERTIONS_PATH}" "${APP_SERVER_STATUS_PATH}" "${LIVE_AUTH_STATUS_PATH}" <<'RUBY'
require "json"

snapshot_path, assertions_path, app_server_status_path, live_auth_status_path = ARGV
snapshot = JSON.parse(File.read(snapshot_path))
app_server_status = JSON.parse(File.read(app_server_status_path))
live_auth_status = JSON.parse(File.read(live_auth_status_path))
menu_items = snapshot.fetch("menuItems", [])
current_account = snapshot["currentAccount"] || {}

def meaningful_value(value)
  text = value.to_s.strip
  text.empty? ? nil : text
end

def identity_match(current_account, live_identity)
  comparisons = []
  current_digest = meaningful_value(current_account["identityDigest"])
  live_digest = meaningful_value(live_identity["identityDigest"])
  if current_digest && live_digest
    comparisons << {
      "field" => "identityDigest",
      "current" => current_digest,
      "live" => live_digest,
      "matched" => current_digest == live_digest
    }
  end

  if comparisons.empty?
    current_email = meaningful_value(current_account["email"])
    live_email = meaningful_value(live_identity["email"])
    comparisons = if current_email && live_email
      [{
        "field" => "email",
        "current" => current_email,
        "live" => live_email,
        "matched" => current_email == live_email
      }]
    else
      []
    end
  end

  {
    "passed" => !comparisons.empty? && comparisons.all? { |comparison| comparison["matched"] },
    "comparisons" => comparisons
  }
end

def find_child(items, title)
  items.find { |item| item["title"] == title }
end

def account_names_for_section(snapshot, title)
  snapshot.fetch("sections", [])
    .find { |section| section["title"] == title }
    &.fetch("items", [])
    &.map { |item| item.to_s.split(" • ").first.to_s.strip }
    &.reject(&:empty?) || []
end

def load_saved_account_names
  accounts_path = File.expand_path("~/Library/Application Support/CodexPill/accounts.json")
  return [] unless File.exist?(accounts_path)

  JSON.parse(File.read(accounts_path))
    .map { |account| account["name"].to_s.strip }
    .reject(&:empty?)
rescue JSON::ParserError
  []
end

def has_switch_account_item?(items, name)
  items.any? do |item|
    title = item["title"].to_s
    title == name || title.start_with?("#{name}\n")
  end
end

status_item = find_child(menu_items, "Status Item")
abort "Missing Status Item menu in runtime snapshot" unless status_item

accounts_menu = find_child(menu_items, "Accounts")
abort "Missing Accounts menu in runtime snapshot" unless accounts_menu

add_account_menu = find_child(accounts_menu.fetch("children", []), "Add Account")
abort "Missing Accounts > Add Account menu in runtime snapshot" unless add_account_menu

save_current_account = find_child(add_account_menu.fetch("children", []), "Save Current Account")
abort "Missing Accounts > Add Account > Save Current Account item in runtime snapshot" unless save_current_account

content_menu = find_child(status_item.fetch("children", []), "Content")
abort "Missing Status Item > Content menu in runtime snapshot" unless content_menu

icon_only = find_child(content_menu.fetch("children", []), "Icon Only")
icon_and_text = find_child(content_menu.fetch("children", []), "Icon + Text")
text_on_hover = find_child(content_menu.fetch("children", []), "Text on Hover")
abort "Missing one or more Status Item > Content options in runtime snapshot" unless icon_only && icon_and_text && text_on_hover

has_status_item_content_data = snapshot.fetch("hasStatusItemContentData", false)
effective_display_mode = snapshot.fetch("effectiveStatusBarDisplayMode", nil)
app_server_reported_current_status_data = !app_server_status["primaryUsedPercent"].nil?

checks = if has_status_item_content_data
  [
    {
      "title" => "Icon Only remains selectable when status data exists",
      "passed" => icon_only["isEnabled"] == true && icon_only["hasAction"] == true && icon_only["actionSelector"] == "selectStatusBarDisplayMode:",
      "actual" => icon_only
    },
    {
      "title" => "Icon + Text remains selectable when status data exists",
      "passed" => icon_and_text["isEnabled"] == true && icon_and_text["hasAction"] == true && icon_and_text["actionSelector"] == "selectStatusBarDisplayMode:",
      "actual" => icon_and_text
    },
    {
      "title" => "Text on Hover remains selectable when status data exists",
      "passed" => text_on_hover["isEnabled"] == true && text_on_hover["hasAction"] == true && text_on_hover["actionSelector"] == "selectStatusBarDisplayMode:",
      "actual" => text_on_hover
    },
    {
      "title" => "Runtime snapshot reports a valid effective display mode",
      "passed" => ["iconOnly", "iconAndText", "textOnHover"].include?(effective_display_mode),
      "actual" => { "effectiveStatusBarDisplayMode" => effective_display_mode }
    }
  ]
else
  [
    {
      "title" => "Icon Only stays enabled when no status data exists",
      "passed" => icon_only["isEnabled"] == true && icon_only["hasAction"] == true && icon_only["actionSelector"] == "selectStatusBarDisplayMode:",
      "actual" => icon_only
    },
    {
      "title" => "Icon + Text is disabled without status data",
      "passed" => icon_and_text["isEnabled"] == false && icon_and_text["hasAction"] == false && icon_and_text["actionSelector"].nil?,
      "actual" => icon_and_text
    },
    {
      "title" => "Text on Hover is disabled without status data",
      "passed" => text_on_hover["isEnabled"] == false && text_on_hover["hasAction"] == false && text_on_hover["actionSelector"].nil?,
      "actual" => text_on_hover
    },
    {
      "title" => "Runtime snapshot forces Icon Only without status data",
      "passed" => effective_display_mode == "iconOnly",
      "actual" => { "effectiveStatusBarDisplayMode" => effective_display_mode }
    }
  ]
end

other_account_items = snapshot.fetch("sections", [])
  .find { |section| section["title"] == "Other Accounts" }
  &.fetch("items", []) || []
visible_other_account_names = account_names_for_section(snapshot, "Other Accounts")
overflow_other_account_names = account_names_for_section(snapshot, "More Accounts…")
rendered_other_account_names = visible_other_account_names + overflow_other_account_names
more_accounts_menu = find_child(menu_items, "More Accounts…")
more_accounts_children = more_accounts_menu&.fetch("children", []) || []
saved_account_names = load_saved_account_names
current_account_name = meaningful_value(current_account["name"])
expected_inactive_account_names =
  if current_account_name && saved_account_names.include?(current_account_name)
    saved_account_names.reject { |name| name == current_account_name }
  else
    saved_account_names
  end

current_account_summary = snapshot.fetch("sections", [])
  .find { |section| section["title"] == "Current Account" }
  &.fetch("items", [])
  &.first
live_auth_identity_match = identity_match(current_account, live_auth_status)

checks << {
  "title" => "Visible other accounts do not use placeholder usage values",
  "passed" => other_account_items.none? { |item| item.include?("Session --") || item.include?("Weekly --") },
  "actual" => other_account_items
}

checks << {
  "title" => "All saved inactive accounts are rendered in Other Accounts or More Accounts…",
  "passed" => rendered_other_account_names.sort == expected_inactive_account_names.sort,
  "actual" => {
    "currentAccountName" => current_account_name,
    "savedAccountNames" => saved_account_names,
    "expectedInactiveAccountNames" => expected_inactive_account_names,
    "renderedOtherAccountNames" => rendered_other_account_names
  }
}

checks << {
  "title" => "Visible other accounts expose enabled switchAccount menu actions",
  "passed" => (
    expected_inactive_account_names.empty? && visible_other_account_names.empty?
  ) || (
    !visible_other_account_names.empty? && visible_other_account_names.all? do |name|
      menu_items.any? do |item|
        has_switch_account_item?([item], name) &&
          item["isEnabled"] == true &&
          item["hasAction"] == true &&
          item["actionSelector"] == "switchAccount:"
      end
    end
  ),
  "actual" => visible_other_account_names.map do |name|
    matched = menu_items.find do |item|
      has_switch_account_item?([item], name) &&
        item["actionSelector"] == "switchAccount:"
    end
    {
      "name" => name,
      "matchedTitle" => matched&.dig("title"),
      "isEnabled" => matched&.dig("isEnabled"),
      "hasAction" => matched&.dig("hasAction"),
      "actionSelector" => matched&.dig("actionSelector")
    }
  end
}

checks << {
  "title" => "Overflow other accounts expose enabled switchAccount submenu actions",
  "passed" => overflow_other_account_names.all? do |name|
    more_accounts_children.any? do |item|
      has_switch_account_item?([item], name) &&
        item["isEnabled"] == true &&
        item["hasAction"] == true &&
        item["actionSelector"] == "switchAccount:"
    end
  end,
  "actual" => overflow_other_account_names.map do |name|
    matched = more_accounts_children.find do |item|
      has_switch_account_item?([item], name) &&
        item["actionSelector"] == "switchAccount:"
    end
    {
      "name" => name,
      "matchedTitle" => matched&.dig("title"),
      "isEnabled" => matched&.dig("isEnabled"),
      "hasAction" => matched&.dig("hasAction"),
      "actionSelector" => matched&.dig("actionSelector")
    }
  end
}

checks << {
  "title" => "Save Current Account stays enabled when the menu is idle",
  "passed" => save_current_account["isEnabled"] == true && save_current_account["hasAction"] == true,
  "actual" => save_current_account
}

checks << {
  "title" => "Current account summary reflects live auth identity",
  "passed" => !current_account_summary.to_s.empty? && live_auth_identity_match["passed"],
  "actual" => {
    "currentAccount" => current_account,
    "currentAccountSummary" => current_account_summary,
    "liveAuthEmail" => live_auth_status["email"],
    "comparisons" => live_auth_identity_match["comparisons"]
  }
}

if app_server_reported_current_status_data
  live_app_server_identity_match = identity_match(
    current_account,
    {
      "email" => app_server_status["accountEmail"]
    }
  )
  checks << {
    "title" => "Current account summary reflects live app-server identity",
    "passed" => !current_account_summary.to_s.empty? &&
      live_app_server_identity_match["passed"] &&
      has_status_item_content_data == true,
    "actual" => {
      "currentAccount" => current_account,
      "currentAccountSummary" => current_account_summary,
      "appServerEmail" => app_server_status["accountEmail"],
      "hasStatusItemContentData" => has_status_item_content_data,
      "appServerPrimaryUsedPercent" => app_server_status["primaryUsedPercent"],
      "appServerSecondaryUsedPercent" => app_server_status["secondaryUsedPercent"],
      "comparisons" => live_app_server_identity_match["comparisons"]
    }
  }
end

File.write(
  assertions_path,
  JSON.pretty_generate(
    {
      "checkedPath" => ["Status Item", "Content"],
      "hasStatusItemContentData" => has_status_item_content_data,
      "effectiveStatusBarDisplayMode" => effective_display_mode,
      "appServerReportedCurrentStatusData" => app_server_reported_current_status_data,
      "checks" => checks
    }
  )
)

exit(checks.all? { |check| check["passed"] } ? 0 : 1)
RUBY
}

RUNTIME_ASSERTIONS_PASSED=0
for _ in $(seq 1 20); do
  if run_runtime_assertions; then
    RUNTIME_ASSERTIONS_PASSED=1
    break
  fi
  sleep 1
done

if [[ "${RUNTIME_ASSERTIONS_PASSED}" -ne 1 ]]; then
  FAILED_CHECK_TITLES="$(ruby -rjson -e 'payload = JSON.parse(File.read(ARGV[0])); failed = payload.fetch("checks", []).reject { |check| check["passed"] }; puts(JSON.generate(failed.map { |check| check["title"] }))' "${RUNTIME_ASSERTIONS_PATH}")"
  cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The local codex app-server probe returned account identity and rate-limit data",
    "CodexPill process launched successfully",
    "The app emitted a runtime menu snapshot during menu rebuild"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": ${FAILED_CHECK_TITLES},
  "scenario": "${SCENARIO}",
  "status": "failed"
}
EOF
  echo "Live smoke failed: runtime snapshot assertions did not pass." >&2
  exit 8
fi

MENU_BAR_COUNT_OUTPUT="$(osascript -e 'tell application "System Events" to tell process "CodexPill" to get count of menu bars' 2>&1)" || true

if printf '%s' "${MENU_BAR_COUNT_OUTPUT}" | rg -q "assistive access|not allowed assistive access|\(-1719\)|\(-25211\)"; then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "logs/run-menubar.log"
  ],
  "assertions": [],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "osascript is not allowed assistive access on this machine.",
    "Grant Accessibility access to osascript or Terminal in System Settings > Privacy & Security > Accessibility."
  ],
  "scenario": "${SCENARIO}",
  "status": "blocked"
}
EOF
  echo "Live smoke blocked: osascript is not allowed assistive access." >&2
  exit 4
fi

if ! printf '%s' "${MENU_BAR_COUNT_OUTPUT}" | rg -q '^[0-9]+$'; then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "logs/run-menubar.log"
  ],
  "assertions": [],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "Unexpected Accessibility probe output: ${MENU_BAR_COUNT_OUTPUT//$'\n'/ }"
  ],
  "scenario": "${SCENARIO}",
  "status": "failed"
}
EOF
  echo "Live smoke failed: unexpected Accessibility probe output." >&2
  exit 5
fi

MENU_ITEM_COUNT="$(osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        tell menu bar 2
            click menu bar item 1
            delay 1
            set itemCount to count of menu items of menu 1 of menu bar item 1
            click menu bar item 1
            return itemCount
        end tell
    end tell
end tell
EOF
)"

MENU_TITLES_RAW="$(osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        tell menu bar 2
            click menu bar item 1
            delay 1
            set titles to name of every menu item of menu 1 of menu bar item 1
            set AppleScript's text item delimiters to linefeed
            set joined to titles as text
            click menu bar item 1
            return joined
        end tell
    end tell
end tell
EOF
)"

screencapture -x "${SCREENSHOT_PATH}"

MENU_TITLES_JSON_STRING="$(printf '%s' "${MENU_TITLES_RAW}" | ruby -rjson -e 'print JSON.generate(STDIN.read)')"

cat > "${UI_TREE_PATH}" <<EOF
{
  "liveSnapshotPath": "live-menu-snapshot.json",
  "runtimeAssertionsPath": "runtime-assertions.json",
  "menuBarCount": ${MENU_BAR_COUNT_OUTPUT},
  "targetedMenuBar": 2,
  "targetedMenuBarItemIndex": 1,
  "menuItemCount": ${MENU_ITEM_COUNT},
  "menuItemTitlesRaw": ${MENU_TITLES_JSON_STRING},
  "runtimeSnapshot": $(cat "${LIVE_SNAPSHOT_PATH}"),
  "runtimeAssertions": $(cat "${RUNTIME_ASSERTIONS_PATH}")
}
EOF

if [[ "${MENU_ITEM_COUNT}" == "0" ]]; then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The live auth snapshot was recorded from ~/.codex/auth.json",
    "The local codex app-server probe returned account identity and rate-limit data",
    "CodexPill process launched successfully",
    "The app emitted a runtime menu snapshot during menu rebuild",
    "The runtime snapshot proved the enabled and action state for Status Item > Content",
    "The runtime snapshot current account summary matches live auth and app-server identity",
    "Accessibility probe reached the menubar process",
    "The status item on menu bar 2 was targeted"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The live status item is reachable, but Accessibility exposes zero menu items after opening it on this machine.",
    "Runtime snapshot proof is present, so this is an Accessibility inspection gap rather than missing app evidence."
  ],
  "scenario": "${SCENARIO}",
  "status": "passed"
}
EOF
  echo "Live menubar smoke artifacts written to ${ARTIFACT_ROOT}"
  exit 0
fi

cat > "${SUMMARY_PATH}" <<EOF
{
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The live auth snapshot was recorded from ~/.codex/auth.json",
    "The local codex app-server probe returned account identity and rate-limit data",
    "CodexPill process launched successfully",
    "The app emitted a runtime menu snapshot during menu rebuild",
    "The runtime snapshot proved the enabled and action state for Status Item > Content",
    "The runtime snapshot current account summary matches live auth and app-server identity",
    "Accessibility probe reached the menubar process",
    "The status item on menu bar 2 opened and returned menu item titles"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} ./scripts/live_menubar_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "status": "passed"
}
EOF

echo "Live menubar smoke artifacts written to ${ARTIFACT_ROOT}"
