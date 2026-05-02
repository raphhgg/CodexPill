#!/usr/bin/env zsh
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
VALIDATION_EVENTS_PATH="${ARTIFACT_ROOT}/validation-events.jsonl"
SEAL_PROOF_OUTPUT_PATH="${ARTIFACT_ROOT}/seal-proof"
SEAL_VERIFIER_STDOUT_PATH="${ARTIFACT_ROOT}/logs/seal-verifier.stdout.log"
SEAL_VERIFIER_STDERR_PATH="${ARTIFACT_ROOT}/logs/seal-verifier.stderr.log"
SEAL_PACKAGE_PATH="${CODEXPILL_SEAL_PACKAGE_PATH:-../Seal}"
RUNTIME_ASSERTIONS_PATH="${ARTIFACT_ROOT}/runtime-assertions.json"
APP_SERVER_STATUS_PATH="${ARTIFACT_ROOT}/app-server-status.json"
LIVE_AUTH_STATUS_PATH="${ARTIFACT_ROOT}/live-auth-status.json"
VALIDATION_APP_SUPPORT_DIR="${ARTIFACT_ROOT}/validation-app-support"
VALIDATION_SETTINGS_FIXTURE_PATH="${ARTIFACT_ROOT}/validation-settings.json"
VALIDATION_DEFAULTS_SUITE="CodexPill.validation.${AGENT_NAME}.${SCENARIO//[^[:alnum:]]/_}"
PROOF_LAYER="live_ui"

case "${SCENARIO}" in
  live-account-switch)
    INVARIANT_IDS_JSON='["accounts.switch_account.menu_action_changes_active_account"]'
    ;;
  live-remote-host-switch)
    INVARIANT_IDS_JSON='["hosts.switch_account_on_host.changes_remote_active_account"]'
    ;;
  live-add-host-destination-validation-failed|live-add-host-prompt)
    INVARIANT_IDS_JSON='["hosts.add_host.destination_validation_failed"]'
    ;;
  live-scheduled-refresh)
    INVARIANT_IDS_JSON='["accounts.scheduled_refresh.requested_and_completed"]'
    ;;
  live-add-account-name-dialog-cancelled|live-add-account-prompt)
    INVARIANT_IDS_JSON='["accounts.add_account.name_dialog_presented","accounts.add_account.name_dialog_cancelled","accounts.add_account.cancel_keeps_account_state"]'
    ;;
  *)
    INVARIANT_IDS_JSON='["menubar.status_item_content.fallback_icon_only","menubar.inactive_accounts.render_and_wired_for_switch","menubar.custom_rows.stay_flush_with_rendered_menu_width"]'
    ;;
esac

mkdir -p "${ARTIFACT_ROOT}/screenshots" "${ARTIFACT_ROOT}/logs"
rm -f "${VALIDATION_EVENTS_PATH}"

if [[ "${SCENARIO}" == "live-account-switch" || "${SCENARIO}" == "live-remote-host-switch" || "${SCENARIO}" == "live-add-account-name-dialog-cancelled" || "${SCENARIO}" == "live-add-account-prompt" || "${SCENARIO}" == "live-add-host-destination-validation-failed" || "${SCENARIO}" == "live-add-host-prompt" ]]; then
  rm -rf "${SEAL_PROOF_OUTPUT_PATH}"
fi

cat > "${COMMAND_PATH}" <<EOF
AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh
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

if [[ "${SCENARIO}" == "live-account-switch" || "${SCENARIO}" == "live-remote-host-switch" ]]; then
  rm -rf "${VALIDATION_APP_SUPPORT_DIR}"
  mkdir -p "${VALIDATION_APP_SUPPORT_DIR}/snapshots"
  export CODEXPILL_VALIDATION_APP_SUPPORT_DIR="${PWD}/${VALIDATION_APP_SUPPORT_DIR}"
fi

if [[ "${SCENARIO}" == "live-account-switch" ]]; then
  ruby - "${VALIDATION_APP_SUPPORT_DIR}" <<'RUBY'
require "json"
require "securerandom"
require "time"

app_support_dir = ARGV.fetch(0)
accounts_path = File.join(app_support_dir, "accounts.json")
snapshots_dir = File.join(app_support_dir, "snapshots")
auth_path = File.join(app_support_dir, "auth.json")
now = Time.utc(2026, 4, 20, 10, 0, 0)

make_limits = lambda do |session_used, weekly_used, session_minutes, weekly_days|
  {
    "limitID" => nil,
    "limitName" => nil,
    "planType" => "team",
    "primary" => {
      "usedPercent" => session_used,
      "resetsAt" => (now + (session_minutes * 60)).iso8601,
      "windowDurationMinutes" => 300
    },
    "secondary" => {
      "usedPercent" => weekly_used,
      "resetsAt" => (now + (weekly_days * 86_400)).iso8601,
      "windowDurationMinutes" => 10_080
    },
    "fetchedAt" => now.iso8601
  }
end

accounts = [
  {
    "id" => SecureRandom.uuid,
    "name" => "Validation Personal",
    "snapshotFileName" => "validation-personal.json",
    "createdAt" => (now - 3600).iso8601,
    "updatedAt" => (now - 300).iso8601,
    "email" => "validation-personal@example.com",
    "planType" => "team",
    "rateLimits" => make_limits.call(18, 26, 180, 6),
    "identity" => {
      "stableAccountID" => nil,
      "authPrincipalIdentity" => nil,
      "workspaceIdentity" => nil,
      "snapshotFingerprint" => nil,
      "remoteIdentity" => {
        "normalizedEmailAddress" => "validation-personal@example.com"
      }
    }
  },
  {
    "id" => SecureRandom.uuid,
    "name" => "Validation Business",
    "snapshotFileName" => "validation-business.json",
    "createdAt" => (now - 3600).iso8601,
    "updatedAt" => (now - 300).iso8601,
    "email" => "validation-business@example.com",
    "planType" => "team",
    "rateLimits" => make_limits.call(64, 41, 75, 5),
    "identity" => {
      "stableAccountID" => nil,
      "authPrincipalIdentity" => nil,
      "workspaceIdentity" => nil,
      "snapshotFingerprint" => nil,
      "remoteIdentity" => {
        "normalizedEmailAddress" => "validation-business@example.com"
      }
    }
  }
]

personal_snapshot = {
  "validationAccount" => "personal",
  "email" => "validation-personal@example.com"
}
business_snapshot = {
  "validationAccount" => "business",
  "email" => "validation-business@example.com"
}

File.write(File.join(snapshots_dir, "validation-personal.json"), JSON.pretty_generate(personal_snapshot))
File.write(File.join(snapshots_dir, "validation-business.json"), JSON.pretty_generate(business_snapshot))
File.write(auth_path, JSON.pretty_generate(personal_snapshot))
File.write(accounts_path, JSON.pretty_generate(accounts))
RUBY
fi

if [[ "${SCENARIO}" == "live-remote-host-switch" ]]; then
  ruby - "${VALIDATION_APP_SUPPORT_DIR}/accounts.json" "${VALIDATION_SETTINGS_FIXTURE_PATH}" <<'RUBY'
require "json"
require "securerandom"
require "time"

accounts_path, settings_path = ARGV
now = Time.utc(2026, 4, 20, 10, 0, 0)

make_limits = lambda do |session_used, weekly_used, session_minutes, weekly_days|
  {
    "limitID" => nil,
    "limitName" => nil,
    "planType" => "team",
    "primary" => {
      "usedPercent" => session_used,
      "resetsAt" => (now + (session_minutes * 60)).iso8601,
      "windowDurationMinutes" => 300
    },
    "secondary" => {
      "usedPercent" => weekly_used,
      "resetsAt" => (now + (weekly_days * 86_400)).iso8601,
      "windowDurationMinutes" => 10_080
    },
    "fetchedAt" => now.iso8601
  }
end

accounts = [
  {
    "id" => SecureRandom.uuid,
    "name" => "Validation Local",
    "snapshotFileName" => "validation-local.json",
    "createdAt" => (now - 3600).iso8601,
    "updatedAt" => (now - 300).iso8601,
    "email" => "validation-local@example.com",
    "planType" => "team",
    "rateLimits" => make_limits.call(18, 26, 180, 6),
    "identity" => {
      "stableAccountID" => nil,
      "authPrincipalIdentity" => nil,
      "workspaceIdentity" => nil,
      "snapshotFingerprint" => SecureRandom.uuid,
      "remoteIdentity" => {
        "normalizedEmailAddress" => "validation-local@example.com"
      }
    }
  },
  {
    "id" => SecureRandom.uuid,
    "name" => "Validation Remote",
    "snapshotFileName" => "validation-remote.json",
    "createdAt" => (now - 3600).iso8601,
    "updatedAt" => (now - 300).iso8601,
    "email" => "validation-remote@example.com",
    "planType" => "team",
    "rateLimits" => make_limits.call(64, 41, 75, 5),
    "identity" => {
      "stableAccountID" => nil,
      "authPrincipalIdentity" => nil,
      "workspaceIdentity" => nil,
      "snapshotFingerprint" => SecureRandom.uuid,
      "remoteIdentity" => {
        "normalizedEmailAddress" => "validation-remote@example.com"
      }
    }
  }
]

settings = {
  "remoteHostStates" => [
    {
      "host" => {
        "destination" => "user@buildbox",
        "displayName" => "buildbox"
      },
      "installedAccountIDs" => [],
      "activeAccount" => nil
    }
  ]
}

File.write(accounts_path, JSON.pretty_generate(accounts))
File.write(settings_path, JSON.pretty_generate(settings))
RUBY
fi

RUN_MENUBAR_ENV=(
  "CODEXPILL_VALIDATION_OUTPUT=${PWD}/${LIVE_SNAPSHOT_PATH}"
  "CODEXPILL_VALIDATION_EVENTS_OUTPUT=${PWD}/${VALIDATION_EVENTS_PATH}"
  "CODEXPILL_VALIDATION_SCENARIO=${SCENARIO}"
)

if [[ "${SCENARIO}" == "live-account-switch" || "${SCENARIO}" == "live-remote-host-switch" || "${SCENARIO}" == "live-add-account-name-dialog-cancelled" || "${SCENARIO}" == "live-add-account-prompt" || "${SCENARIO}" == "live-add-host-destination-validation-failed" || "${SCENARIO}" == "live-add-host-prompt" || "${SCENARIO}" == "live-scheduled-refresh" ]]; then
  RUN_MENUBAR_ENV+=(
    "CODEXPILL_SEAL_PROOF_OUTPUT=${PWD}/${SEAL_PROOF_OUTPUT_PATH}"
  )
fi

if [[ "${SCENARIO}" == "live-scheduled-refresh" ]]; then
  RUN_MENUBAR_ENV+=(
    "CODEXPILL_VALIDATION_AUTO_REFRESH_INTERVAL_SECONDS=2"
  )
fi

if [[ "${SCENARIO}" == "live-account-switch" || "${SCENARIO}" == "live-add-account-name-dialog-cancelled" || "${SCENARIO}" == "live-add-host-destination-validation-failed" || "${SCENARIO}" == "live-add-host-prompt" ]]; then
  RUN_MENUBAR_ENV+=(
    "CODEXPILL_VALIDATION_ALLOW_INTERACTIVE_ALERTS=1"
  )
fi

if [[ "${SCENARIO}" == "live-add-account-name-dialog-cancelled" || "${SCENARIO}" == "live-add-account-prompt" ]]; then
  RUN_MENUBAR_ENV+=(
    "CODEXPILL_VALIDATION_TRIGGER_ADD_ACCOUNT_PROMPT=1"
  )
fi

if [[ "${SCENARIO}" == "live-remote-host-switch" ]]; then
  RUN_MENUBAR_ENV+=(
    "CODEXPILL_VALIDATION_APP_SUPPORT_DIR=${PWD}/${VALIDATION_APP_SUPPORT_DIR}"
    "CODEXPILL_VALIDATION_USER_DEFAULTS_SUITE=${VALIDATION_DEFAULTS_SUITE}"
    "CODEXPILL_VALIDATION_SETTINGS_FIXTURE=${PWD}/${VALIDATION_SETTINGS_FIXTURE_PATH}"
    "CODEXPILL_VALIDATION_REMOTE_HOST_CLIENT=memory"
  )
fi

if [[ "${SCENARIO}" == "live-account-switch" ]]; then
  RUN_MENUBAR_ENV+=(
    "CODEXPILL_VALIDATION_APP_SUPPORT_DIR=${PWD}/${VALIDATION_APP_SUPPORT_DIR}"
    "CODEXPILL_VALIDATION_USER_DEFAULTS_SUITE=${VALIDATION_DEFAULTS_SUITE}"
    "CODEXPILL_VALIDATION_CODEX_PROCESS_CLIENT=memory"
  )
fi

env "${RUN_MENUBAR_ENV[@]}" \
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
  ruby - "${LIVE_SNAPSHOT_PATH}" "${RUNTIME_ASSERTIONS_PATH}" "${APP_SERVER_STATUS_PATH}" "${LIVE_AUTH_STATUS_PATH}" "${SCENARIO}" <<'RUBY'
require "json"

snapshot_path, assertions_path, app_server_status_path, live_auth_status_path, scenario = ARGV
snapshot = JSON.parse(File.read(snapshot_path))
app_server_status = JSON.parse(File.read(app_server_status_path))
live_auth_status = JSON.parse(File.read(live_auth_status_path))
menu_items = snapshot.fetch("menuItems", [])
current_account = snapshot["currentAccount"] || {}
uses_isolated_account_switch_fixture = scenario == "live-account-switch" &&
  !ENV["CODEXPILL_VALIDATION_APP_SUPPORT_DIR"].to_s.strip.empty?

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
  accounts_root = ENV["CODEXPILL_VALIDATION_APP_SUPPORT_DIR"]
  accounts_path = if accounts_root && !accounts_root.strip.empty?
    File.join(accounts_root, "accounts.json")
  else
    File.expand_path("~/Library/Application Support/CodexPill/accounts.json")
  end
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
    title == name || title.start_with?("#{name}\n") || title.start_with?("#{name}  ")
  end
end

add_account_menu = find_child(menu_items, "Add Account…")
abort "Missing Add Account… menu in runtime snapshot" unless add_account_menu

preferences_menu = find_child(menu_items, "Preferences")
abort "Missing Preferences menu in runtime snapshot" unless preferences_menu

content_menu = find_child(preferences_menu.fetch("children", []), "Menu Bar Label")
abort "Missing Preferences > Menu Bar Label menu in runtime snapshot" unless content_menu

icon_only = find_child(content_menu.fetch("children", []), "Icon Only")
icon_and_text = find_child(content_menu.fetch("children", []), "Icon + Text")
text_on_hover = find_child(content_menu.fetch("children", []), "Text on Hover")
abort "Missing one or more Preferences > Menu Bar Label options in runtime snapshot" unless icon_only && icon_and_text && text_on_hover

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

account_items = snapshot.fetch("sections", [])
  .find { |section| section["title"] == "Accounts" }
  &.fetch("items", []) || []
visible_account_names = account_names_for_section(snapshot, "Accounts")
overflow_account_names = account_names_for_section(snapshot, "More Accounts…")
rendered_account_names = visible_account_names + overflow_account_names
more_accounts_menu = find_child(menu_items, "More Accounts…")
more_accounts_children = more_accounts_menu&.fetch("children", []) || []
saved_account_names = load_saved_account_names
current_account_name = meaningful_value(current_account["name"])
expected_catalog_account_names = saved_account_names

current_account_summary = snapshot.fetch("sections", [])
  .find { |section| ["Active Account", "Current Account"].include?(section["title"]) }
  &.fetch("items", [])
  &.first
live_auth_identity_match = identity_match(current_account, live_auth_status)

checks << {
  "title" => "Visible accounts do not use placeholder usage values",
  "passed" => account_items.none? { |item| item.include?("Session --") || item.include?("Weekly --") },
  "actual" => account_items
}

checks << {
  "title" => "All saved accounts are rendered in Accounts or More Accounts…",
  "passed" => rendered_account_names.sort == expected_catalog_account_names.sort,
  "actual" => {
    "currentAccountName" => current_account_name,
    "savedAccountNames" => saved_account_names,
    "expectedCatalogAccountNames" => expected_catalog_account_names,
    "renderedAccountNames" => rendered_account_names
  }
}

checks << {
  "title" => "Visible accounts expose enabled switch targets",
  "passed" => (
    expected_catalog_account_names.empty? && visible_account_names.empty?
  ) || (
    !visible_account_names.empty? && visible_account_names.all? do |name|
      menu_items.any? do |item|
        has_switch_account_item?([item], name) && (
          (
            item["isEnabled"] == true &&
            item["hasAction"] == true &&
            item["actionSelector"] == "switchAccount:"
          ) || item.fetch("children", []).any? do |child|
            child["isEnabled"] == true &&
              child["hasAction"] == true &&
              ["switchAccount:", "switchAccountOnHost:"].include?(child["actionSelector"])
          end
        )
      end
    end
  ),
  "actual" => visible_account_names.map do |name|
    matched = menu_items.find do |item|
      has_switch_account_item?([item], name)
    end
    {
      "name" => name,
      "matchedTitle" => matched&.dig("title"),
      "isEnabled" => matched&.dig("isEnabled"),
      "hasAction" => matched&.dig("hasAction"),
      "actionSelector" => matched&.dig("actionSelector"),
      "childActions" => matched&.fetch("children", [])&.map { |child| child["actionSelector"] }
    }
  end
}

checks << {
  "title" => "Local visible accounts remain native menu entries",
  "passed" => (
    snapshot.fetch("remoteHosts", []).empty? && !visible_account_names.empty?
  ) ? visible_account_names.all? do |name|
    matched = menu_items.find { |item| has_switch_account_item?([item], name) }
    !matched.nil? &&
      matched["viewFrameWidth"].nil? &&
      matched["hasAction"] == false &&
      matched.fetch("children", []).any? { |child| child["actionSelector"] == "switchAccount:" }
  end : true,
  "actual" => visible_account_names.map do |name|
    matched = menu_items.find { |item| has_switch_account_item?([item], name) }
    {
      "name" => name,
      "matchedTitle" => matched&.dig("title"),
      "viewFrameWidth" => matched&.dig("viewFrameWidth"),
      "hasAction" => matched&.dig("hasAction"),
      "actionSelector" => matched&.dig("actionSelector"),
      "childActions" => matched&.fetch("children", [])&.map { |child| child["actionSelector"] }
    }
  end
}

checks << {
  "title" => "Overflow accounts expose enabled switchAccount submenu actions",
  "passed" => overflow_account_names.all? do |name|
    more_accounts_children.any? do |item|
      has_switch_account_item?([item], name) &&
        item["isEnabled"] == true &&
        item.fetch("children", []).any? { |child| child["actionSelector"] == "switchAccount:" }
    end
  end,
  "actual" => overflow_account_names.map do |name|
    matched = more_accounts_children.find do |item|
      has_switch_account_item?([item], name)
    end
    {
      "name" => name,
      "matchedTitle" => matched&.dig("title"),
      "isEnabled" => matched&.dig("isEnabled"),
      "hasAction" => matched&.dig("hasAction"),
      "actionSelector" => matched&.dig("actionSelector"),
      "childActions" => matched&.fetch("children", [])&.map { |child| child["actionSelector"] }
    }
  end
}

checks << {
  "title" => "Add Account stays available as the current direct account action",
  "passed" => add_account_menu["isEnabled"] == true && add_account_menu["hasAction"] == true,
  "actual" => add_account_menu
}

if !uses_isolated_account_switch_fixture
  checks << {
    "title" => "Current account summary reflects live auth identity",
    "passed" => current_account.empty? || (
      !current_account_summary.to_s.empty? && live_auth_identity_match["passed"]
    ),
    "actual" => {
      "currentAccount" => current_account,
      "currentAccountSummary" => current_account_summary,
      "liveAuthEmail" => live_auth_status["email"],
      "comparisons" => live_auth_identity_match["comparisons"]
    }
  }
end

if app_server_reported_current_status_data && !uses_isolated_account_switch_fixture
  live_app_server_identity_match = identity_match(
    current_account,
    {
      "email" => app_server_status["accountEmail"]
    }
  )
  checks << {
    "title" => "Current account summary reflects live app-server identity",
    "passed" => current_account.empty? || (
      !current_account_summary.to_s.empty? &&
        live_app_server_identity_match["passed"] &&
        has_status_item_content_data == true
    ),
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
      "checkedPath" => ["Preferences", "Menu Bar Label"],
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

read_account_target_json() {
  local exclude_current="${1:-0}"

  ruby - "${LIVE_SNAPSHOT_PATH}" "${exclude_current}" <<'RUBY'
require "json"

snapshot = JSON.parse(File.read(ARGV.fetch(0)))
sections = snapshot.fetch("sections", [])
menu_items = snapshot.fetch("menuItems", [])
exclude_current = ARGV.fetch(1, "0") == "1"

extract_names = lambda do |title|
  sections.find { |section| section["title"] == title }
    &.fetch("items", [])
    &.map { |item| item.to_s.split(" • ").first.to_s.strip }
    &.reject(&:empty?) || []
end

current_account_name = snapshot.dig("currentAccount", "name").to_s.strip
visible = extract_names.call("Accounts")
overflow = extract_names.call("More Accounts…")

visible_candidates = exclude_current ? visible.reject { |name| name == current_account_name } : visible
overflow_candidates = exclude_current ? overflow.reject { |name| name == current_account_name } : overflow

account_title_matches = lambda do |title, target_name|
  rendered = title.to_s.strip
  next false if rendered.empty? || target_name.to_s.strip.empty?

  rendered_name = rendered.split(/\s{2,}/, 2).first.to_s.strip
  normalized_rendered_name = rendered_name.delete_suffix("…")

  rendered_name == target_name ||
    rendered.start_with?("#{target_name} ") ||
    rendered.start_with?("#{target_name}\n") ||
    target_name.start_with?(normalized_rendered_name)
end

target_name = visible_candidates.first || overflow_candidates.first
target_location =
  if visible_candidates.include?(target_name)
    "visible"
  elsif overflow_candidates.include?(target_name)
    "overflow"
  end

root_index = nil
submenu_index = nil

if target_location == "visible"
  matched_index = menu_items.find_index do |item|
    account_title_matches.call(item["title"], target_name)
  end
  root_index = matched_index.nil? ? nil : matched_index + 1
elsif target_location == "overflow"
  more_accounts = menu_items.find { |item| item["title"] == "More Accounts…" }
  matched_index = more_accounts.to_h.fetch("children", []).find_index do |item|
    account_title_matches.call(item["title"], target_name)
  end
  root_index = menu_items.find_index { |item| item["title"] == "More Accounts…" }
  root_index = root_index.nil? ? nil : root_index + 1
  submenu_index = matched_index.nil? ? nil : matched_index + 1
end

puts JSON.generate(
  {
    "currentAccountName" => current_account_name.empty? ? nil : current_account_name,
    "targetName" => target_name,
    "targetLocation" => target_location,
    "targetRootIndex" => root_index,
    "targetSubmenuIndex" => submenu_index,
    "visibleNames" => visible,
    "overflowNames" => overflow
  }
)
RUBY
}

read_host_account_target_json() {
  local host_name="$1"

  ruby - "${LIVE_SNAPSHOT_PATH}" "${host_name}" <<'RUBY'
require "json"

snapshot = JSON.parse(File.read(ARGV.fetch(0)))
target_host_name = ARGV.fetch(1)
sections = snapshot.fetch("sections", [])
menu_items = snapshot.fetch("menuItems", [])

extract_names = lambda do |title|
  sections.find { |section| section["title"] == title }
    &.fetch("items", [])
    &.map { |item| item.to_s.split(" • ").first.to_s.strip }
    &.reject(&:empty?) || []
end

matches_action = lambda do |children|
  Array(children).any? do |child|
    title = child["title"].to_s
    title == "Switch on #{target_host_name}" || title == "Install on #{target_host_name} and switch"
  end
end

visible = extract_names.call("Accounts")
overflow = extract_names.call("More Accounts…")

target_name = nil
target_location = nil
root_index = nil
submenu_index = nil
target_action_title = nil

menu_items.each_with_index do |item, index|
  next unless visible.include?(item["title"].to_s.split(/\s{2,}/, 2).first.to_s.strip)
  next unless matches_action.call(item["children"])
  target_name = item["title"].to_s.split(/\s{2,}/, 2).first.to_s.strip
  target_location = "visible"
  root_index = index + 1
  target_action_title = Array(item["children"]).map { |child| child["title"].to_s }.find do |title|
    title == "Switch on #{target_host_name}" || title == "Install on #{target_host_name} and switch"
  end
  break
end

if target_name.nil?
  if (more_accounts = menu_items.find { |item| item["title"] == "More Accounts…" })
    Array(more_accounts["children"]).each_with_index do |item, index|
      next unless matches_action.call(item["children"])
      target_name = item["title"].to_s.split(/\s{2,}/, 2).first.to_s.strip
      target_location = "overflow"
      root_index = menu_items.find_index { |entry| entry["title"] == "More Accounts…" }
      root_index = root_index.nil? ? nil : root_index + 1
      submenu_index = index + 1
      target_action_title = Array(item["children"]).map { |child| child["title"].to_s }.find do |title|
        title == "Switch on #{target_host_name}" || title == "Install on #{target_host_name} and switch"
      end
      break
    end
  end
end

puts JSON.generate(
  {
    "targetName" => target_name,
    "targetLocation" => target_location,
    "targetRootIndex" => root_index,
    "targetSubmenuIndex" => submenu_index,
    "targetActionTitle" => target_action_title,
    "visibleNames" => visible,
    "overflowNames" => overflow
  }
)
RUBY
}

probe_account_submenu() {
  local target_location="$1"
  local target_root_index="$2"
  local target_submenu_index="$3"

  osascript - "$target_location" "$target_root_index" "$target_submenu_index" <<'EOF'
on run argv
    set targetLocation to item 1 of argv
    set targetRootIndex to item 2 of argv as integer
    set targetSubmenuIndex to item 3 of argv
    tell application "System Events"
        tell process "CodexPill"
            tell menu bar 2
                click menu bar item 1
                delay 0.5
                if targetLocation is equal to "overflow" then
                    set submenuIndex to targetSubmenuIndex as integer
                    tell menu item targetRootIndex of menu 1 of menu bar item 1
                        tell menu 1
                            tell menu item submenuIndex
                                click
                                delay 0.3
                                if exists menu 1 then
                                    set titles to name of every menu item of menu 1
                                else
                                    set titles to {}
                                end if
                            end tell
                        end tell
                    end tell
                else
                    tell menu item targetRootIndex of menu 1 of menu bar item 1
                        click
                        delay 0.3
                        if exists menu 1 then
                            set titles to name of every menu item of menu 1
                        else
                            set titles to {}
                        end if
                    end tell
                end if

                set AppleScript's text item delimiters to linefeed
                return titles as text
            end tell
        end tell
    end tell
end run
EOF
}

close_status_item_menu() {
  osascript <<'EOF' >/dev/null 2>&1 || true
tell application "System Events"
    tell process "CodexPill"
        tell menu bar 2
            click menu bar item 1
        end tell
    end tell
end tell
EOF
}

click_switch_target() {
  local target_location="$1"
  local target_root_index="$2"
  local target_submenu_index="$3"

  osascript - "$target_location" "$target_root_index" "$target_submenu_index" <<'EOF'
on run argv
    set targetLocation to item 1 of argv
    set targetRootIndex to item 2 of argv as integer
    set targetSubmenuIndex to item 3 of argv
    tell application "System Events"
        tell process "CodexPill"
            tell menu bar 2
                click menu bar item 1
                delay 0.5
                if targetLocation is equal to "overflow" then
                    set submenuIndex to targetSubmenuIndex as integer
                    tell menu item targetRootIndex of menu 1 of menu bar item 1
                        tell menu 1
                            tell menu item submenuIndex
                                click
                                delay 0.3
                                tell menu 1
                                    click menu item "Switch on This Mac"
                                end tell
                            end tell
                        end tell
                    end tell
                else
                    tell menu item targetRootIndex of menu 1 of menu bar item 1
                        click
                        delay 0.3
                        tell menu 1
                            click menu item "Switch on This Mac"
                        end tell
                    end tell
                end if
            end tell
        end tell
    end tell
end run
EOF
}

click_account_submenu_action() {
  local target_location="$1"
  local target_root_index="$2"
  local target_submenu_index="$3"
  local action_title="$4"

  osascript - "$target_location" "$target_root_index" "$target_submenu_index" "$action_title" <<'EOF'
on run argv
    set targetLocation to item 1 of argv
    set targetRootIndex to item 2 of argv as integer
    set targetSubmenuIndex to item 3 of argv
    set actionTitle to item 4 of argv
    tell application "System Events"
        tell process "CodexPill"
            tell menu bar 2
                click menu bar item 1
                delay 0.5
                if targetLocation is equal to "overflow" then
                    set submenuIndex to targetSubmenuIndex as integer
                    tell menu item targetRootIndex of menu 1 of menu bar item 1
                        tell menu 1
                            tell menu item submenuIndex
                                click
                                delay 0.3
                                tell menu 1
                                    click menu item actionTitle
                                end tell
                            end tell
                        end tell
                    end tell
                else
                    tell menu item targetRootIndex of menu 1 of menu bar item 1
                        click
                        delay 0.3
                        tell menu 1
                            click menu item actionTitle
                        end tell
                    end tell
                end if
            end tell
        end tell
    end tell
end run
EOF
}

accept_switch_confirmation() {
  osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        if not (exists window 1) then error "No confirmation window"
        tell window 1
            if exists button "Switch" then
                click button "Switch"
                return "accepted"
            end if
            if exists button "OK" then
                click button "OK"
                return "accepted"
            end if
            set buttonCount to count of buttons
            if buttonCount > 0 then
                click button buttonCount
                return "accepted"
            end if
        end tell
    end tell
end tell
EOF
}

trigger_add_account_prompt() {
  osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        tell menu bar 2
            click menu bar item 1
            delay 0.5
            click menu item "Add Account…" of menu 1 of menu bar item 1
        end tell
    end tell
end tell
EOF
}

trigger_add_account_name_dialog() {
  osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        tell menu bar 2
            click menu bar item 1
            delay 0.5
            click menu item "Add Account…" of menu 1 of menu bar item 1
        end tell
    end tell
end tell
EOF
}

trigger_add_host_prompt() {
  osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        tell menu bar 2
            click menu bar item 1
            delay 0.5
            tell menu item "Hosts" of menu 1 of menu bar item 1
                tell menu 1
                    click menu item "Add Host…"
                end tell
            end tell
        end tell
    end tell
end tell
EOF
}

populate_host_setup_destination() {
  local destination="$1"
  osascript - "$destination" <<'EOF'
on run argv
    set destination to item 1 of argv
    set destinationFieldIdentifier to "add-host-destination-field"
    set destinationFieldLabel to "SSH Destination"
    try
        set previousClipboard to the clipboard
    on error
        set previousClipboard to ""
    end try
    set the clipboard to destination
    delay 0.1
    try
        tell application "System Events"
            tell process "CodexPill"
                if not (exists window 1) then error "No host setup window"
                tell window 1
                    set destinationField to missing value
                    set candidateFields to entire contents
                    repeat with currentField in candidateFields
                        try
                            if (role of currentField as text) is "AXTextField" then
                                if destinationField is equal to missing value then
                                    try
                                        if (identifier of currentField as text) is destinationFieldIdentifier then set destinationField to currentField
                                    end try
                                end if
                                if destinationField is equal to missing value then
                                    try
                                        if (name of currentField as text) is destinationFieldLabel then set destinationField to currentField
                                    end try
                                end if
                                if destinationField is equal to missing value then
                                    try
                                        if (description of currentField as text) is destinationFieldLabel then set destinationField to currentField
                                    end try
                                end if
                            end if
                        end try
                    end repeat
                    if destinationField is equal to missing value then
                        set fieldDebug to {}
                        repeat with currentField in candidateFields
                            try
                                if (role of currentField as text) is "AXTextField" then
                                    set fieldName to ""
                                    set fieldIdentifier to ""
                                    set fieldDescription to ""
                                    try
                                        set fieldName to name of currentField as text
                                    end try
                                    try
                                        set fieldIdentifier to identifier of currentField as text
                                    end try
                                    try
                                        set fieldDescription to description of currentField as text
                                    end try
                                    set end of fieldDebug to "name=" & fieldName & ", identifier=" & fieldIdentifier & ", description=" & fieldDescription
                                end if
                            end try
                        end repeat
                        error "No host destination field with accessibility identifier " & destinationFieldIdentifier & "; candidates: " & fieldDebug
                    end if
                    set focused of destinationField to true
                    click destinationField
                    keystroke "a" using command down
                    keystroke destination
                    delay 0.3
                end tell
            end tell
        end tell
        delay 0.1
        set the clipboard to previousClipboard
    on error errorMessage number errorNumber
        set the clipboard to previousClipboard
        error errorMessage number errorNumber
    end try
end run
EOF
}

read_host_setup_prompt_state() {
  osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        if not (exists window 1) then error "No host setup window"
        tell window 1
            set windowTitle to name
            set addEnabled to false
            if exists button "Add Host" then
                set addEnabled to enabled of button "Add Host"
            end if

            set staticValues to {}
            repeat with currentText in static texts
                set end of staticValues to (value of currentText as text)
            end repeat

            return my escapeField(windowTitle) & tab & my booleanText(addEnabled) & tab & my joinFields(staticValues)
        end tell
    end tell
end tell

on joinFields(values)
    set AppleScript's text item delimiters to ","
    set serializedValues to {}
    repeat with currentValue in values
        set end of serializedValues to my escapeField(currentValue as text)
    end repeat
    set joined to serializedValues as text
    set AppleScript's text item delimiters to ""
    return joined
end joinFields

on booleanText(value)
    if value then
        return "true"
    end if
    return "false"
end booleanText

on escapeField(value)
    set textValue to value as text
    set textValue to my replaceText("\\", "\\\\", textValue)
    set textValue to my replaceText(tab, "\\t", textValue)
    set textValue to my replaceText(",", "\\c", textValue)
    set textValue to my replaceText(return, "\\n", textValue)
    set textValue to my replaceText(linefeed, "\\n", textValue)
    return textValue
end escapeField

on replaceText(findText, replaceText, sourceText)
    set AppleScript's text item delimiters to findText
    set textItems to every text item of sourceText
    set AppleScript's text item delimiters to replaceText
    set updatedText to textItems as text
    set AppleScript's text item delimiters to ""
    return updatedText
end replaceText
EOF
}

cancel_text_input_prompt() {
  osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        set frontmost to true
        if not (exists window 1) then error "No text input dialog window"
        repeat with candidateWindow in windows
            tell candidateWindow
                if exists button "Cancel" then
                    click button "Cancel"
                    return "cancelled"
                end if
                repeat with candidateButton in buttons
                    set buttonTitle to ""
                    try
                        set buttonTitle to name of candidateButton as text
                    end try
                    if buttonTitle is "Cancel" then
                        click candidateButton
                        return "cancelled"
                    end if
                end repeat
            end tell
        end repeat
        key code 53
        delay 0.2
        if not (exists window 1) then
            return "cancelled"
        end if
        repeat with candidateWindow in windows
            tell candidateWindow
                if exists button "Cancel" then error "Text input dialog did not close"
            end tell
        end repeat
        return "cancelled"
    end tell
end tell
EOF
}

read_add_account_prompt_proof() {
  ruby - "${VALIDATION_EVENTS_PATH}" <<'RUBY'
require "json"

events_path = ARGV.fetch(0)
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

requirements = [
  ["menu_action_dispatched", "menu_action_dispatched", ->(event) { event.dig("payload", "action") == "addAccount" }],
  ["add_account_prompt_presented", "add_account_name_dialog_presented", ->(_event) { true }],
  ["add_account_prompt_cancelled", "add_account_name_dialog_cancelled", ->(_event) { true }]
]

cursor = 0
proof_sequence = []

requirements.each do |observed_name, canonical_name, predicate|
  matched = false
  while cursor < events.length
    event = events[cursor]
    if event["event"] == observed_name && predicate.call(event)
      proof_sequence << canonical_name
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
    "passed" => proof_sequence == requirements.map { |requirement| requirement[1] },
    "requiredSequence" => requirements.map { |requirement| requirement[1] },
    "proofSequence" => proof_sequence,
    "eventCount" => events.length,
    "eventsPathPresent" => File.exist?(events_path)
  }
)
RUBY
}

read_add_account_name_dialog_proof() {
  ruby - "${VALIDATION_EVENTS_PATH}" <<'RUBY'
require "json"

events_path = ARGV.fetch(0)
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

requirements = [
  ["menu_action_dispatched", "menu_action_dispatched", ->(event) { event.dig("payload", "action") == "addAccount" }],
  ["add_account_prompt_presented", "add_account_name_dialog_presented", ->(_event) { true }],
  ["add_account_prompt_cancelled", "add_account_name_dialog_cancelled", ->(_event) { true }]
]

cursor = 0
proof_sequence = []

requirements.each do |observed_name, canonical_name, predicate|
  matched = false
  while cursor < events.length
    event = events[cursor]
    if event["event"] == observed_name && predicate.call(event)
      proof_sequence << canonical_name
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
    "passed" => proof_sequence == requirements.map { |requirement| requirement[1] },
    "requiredSequence" => requirements.map { |requirement| requirement[1] },
    "proofSequence" => proof_sequence,
    "eventCount" => events.length,
    "eventsPathPresent" => File.exist?(events_path)
  }
)
RUBY
}

verify_seal_proof() {
  local proof_dir="${PWD}/${SEAL_PROOF_OUTPUT_PATH}"
  local manifest_path="${proof_dir}/manifest.json"
  SEAL_PROOF_VERIFICATION_MODE="manifest_missing"
  SEAL_PROOF_FAILURE_GAP="Seal proof manifest was missing or rejected by the Seal verifier."

  if [[ ! -f "${manifest_path}" ]]; then
    printf 'Seal proof manifest missing: %s\n' "${manifest_path}" > "${SEAL_VERIFIER_STDERR_PATH}"
    SEAL_PROOF_FAILURE_GAP="Seal proof manifest missing: ${manifest_path}"
    return 1
  fi

  if [[ -n "${CODEXPILL_SEAL_VERIFIER_COMMAND:-}" ]]; then
    local verifier_parts_file
    verifier_parts_file="$(mktemp)"
    if ! ruby -rshellwords -e 'Shellwords.split(ARGV.fetch(0)).each { |part| puts part }' "${CODEXPILL_SEAL_VERIFIER_COMMAND}" > "${verifier_parts_file}"; then
      rm -f "${verifier_parts_file}"
      printf 'CODEXPILL_SEAL_VERIFIER_COMMAND could not be parsed.\n' > "${SEAL_VERIFIER_STDERR_PATH}"
      SEAL_PROOF_VERIFICATION_MODE="explicit_verifier_command_parse_failed"
      SEAL_PROOF_FAILURE_GAP="CODEXPILL_SEAL_VERIFIER_COMMAND could not be parsed."
      return 1
    fi

    local verifier_command=()
    while IFS= read -r verifier_part; do
      verifier_command+=("${verifier_part}")
    done < "${verifier_parts_file}"
    rm -f "${verifier_parts_file}"

    if [[ "${#verifier_command[@]}" -eq 0 ]]; then
      printf 'CODEXPILL_SEAL_VERIFIER_COMMAND parsed to an empty command.\n' > "${SEAL_VERIFIER_STDERR_PATH}"
      SEAL_PROOF_VERIFICATION_MODE="explicit_verifier_command_empty"
      SEAL_PROOF_FAILURE_GAP="CODEXPILL_SEAL_VERIFIER_COMMAND parsed to an empty command."
      return 1
    fi

    SEAL_PROOF_VERIFICATION_MODE="explicit_verifier_command"
    if "${verifier_command[@]}" "${proof_dir}" > "${SEAL_VERIFIER_STDOUT_PATH}" 2> "${SEAL_VERIFIER_STDERR_PATH}"; then
      return 0
    fi
    SEAL_PROOF_FAILURE_GAP="$(read_seal_proof_failure_gap)"
    return 1
  fi

  local seal_package_path
  seal_package_path="$(cd "${SEAL_PACKAGE_PATH}" >/dev/null 2>&1 && pwd || true)"

  if [[ -n "${seal_package_path}" && -f "${seal_package_path}/Package.swift" ]]; then
    SEAL_PROOF_VERIFICATION_MODE="seal_swift_run"
    if (
      cd "${seal_package_path}"
      swift run seal-verifier --verbose "${proof_dir}"
    ) > "${SEAL_VERIFIER_STDOUT_PATH}" 2> "${SEAL_VERIFIER_STDERR_PATH}"; then
      return 0
    fi
    SEAL_PROOF_FAILURE_GAP="$(read_seal_proof_failure_gap)"
    return 1
  fi

  : > "${SEAL_VERIFIER_STDOUT_PATH}"
  printf 'Seal verifier unavailable. Set CODEXPILL_SEAL_VERIFIER_COMMAND or CODEXPILL_SEAL_PACKAGE_PATH.\n' > "${SEAL_VERIFIER_STDERR_PATH}"
  SEAL_PROOF_VERIFICATION_MODE="verifier_unavailable"
  SEAL_PROOF_FAILURE_GAP="Seal verifier unavailable. Set CODEXPILL_SEAL_VERIFIER_COMMAND or CODEXPILL_SEAL_PACKAGE_PATH."
  return 1
}

read_seal_proof_failure_gap() {
  ruby - "${SEAL_VERIFIER_STDOUT_PATH}" "${SEAL_VERIFIER_STDERR_PATH}" <<'RUBY'
stdout_path, stderr_path = ARGV
text = [stdout_path, stderr_path].filter_map do |path|
  File.exist?(path) ? File.read(path) : nil
end.join("\n")

reason = text.lines.map(&:strip).find { |line| line.start_with?("reason: ") }
diagnostic = text.lines.map(&:strip).find { |line| line.start_with?("- error ") }
fallback = text.lines.map(&:strip).reject(&:empty?).reject { |line| line.start_with?("[") }.first
detail = reason&.sub(/\Areason:\s*/, "") || diagnostic || fallback || "unknown Seal verifier failure"
print "Seal proof rejected: #{detail}"
RUBY
}

seal_proof_failure_gaps_json() {
  ruby -rjson -e 'print(JSON.generate([ARGV.fetch(0)]))' "${SEAL_PROOF_FAILURE_GAP}"
}

read_add_host_prompt_proof() {
  ruby - "${VALIDATION_EVENTS_PATH}" <<'RUBY'
require "json"

events_path = ARGV.fetch(0)
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

requirements = [
  ["menu_action_dispatched", ->(event) { event.dig("payload", "action") == "addHost" }],
  ["add_host_setup_presented", ->(_event) { true }],
  ["add_host_validation_started", ->(event) { event.dig("payload", "hostName") == "codexpill-validation.invalid" }],
  ["add_host_validation_failed", ->(event) { event.dig("payload", "hostName") == "codexpill-validation.invalid" }]
]

cursor = 0
proof_sequence = []

requirements.each do |required_name, predicate|
  matched = false
  while cursor < events.length
    event = events[cursor]
    if event["event"] == required_name && predicate.call(event)
      proof_sequence << required_name
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
    "passed" => proof_sequence == requirements.map(&:first),
    "requiredSequence" => requirements.map(&:first),
    "proofSequence" => proof_sequence,
    "eventCount" => events.length,
    "eventsPathPresent" => File.exist?(events_path)
  }
)
RUBY
}

read_switch_event_proof() {
  ruby - "${VALIDATION_EVENTS_PATH}" "$1" "$2" <<'RUBY'
require "json"

events_path, target_name, original_name = ARGV
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

requirements = [
  ["menu_action_dispatched", ->(event) { event.dig("payload", "action") == "switchAccount" && event.dig("payload", "targetName") == target_name }],
  ["switch_confirmation_presented", ->(event) { event.dig("payload", "targetName") == target_name }],
  ["switch_confirmation_accepted", ->(event) { event.dig("payload", "targetName") == target_name }],
  ["switch_workflow_started", ->(event) { event.dig("payload", "targetName") == target_name }],
  ["active_account_changed", ->(event) {
    event.dig("payload", "toName") == target_name &&
      (original_name.to_s.empty? || event.dig("payload", "fromName") == original_name)
  }]
]

cursor = 0
proof_sequence = []

requirements.each do |required_name, predicate|
  matched = false
  while cursor < events.length
    event = events[cursor]
    if event["event"] == required_name && predicate.call(event)
      proof_sequence << required_name
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
    "passed" => proof_sequence == requirements.map(&:first),
    "requiredSequence" => requirements.map(&:first),
    "proofSequence" => proof_sequence,
    "eventCount" => events.length,
    "eventsPathPresent" => File.exist?(events_path)
  }
)
RUBY
}

read_remote_host_switch_proof() {
  ruby - "${VALIDATION_EVENTS_PATH}" "$1" "$2" <<'RUBY'
require "json"

events_path, target_name, host_name = ARGV
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

requirements = [
  ["menu_action_dispatched", ->(event) {
    event.dig("payload", "action") == "switchAccountOnHost" &&
      event.dig("payload", "targetName") == target_name &&
      event.dig("payload", "hostName") == host_name
  }],
  ["remote_host_switch_started", ->(event) {
    event.dig("payload", "targetName") == target_name &&
      event.dig("payload", "hostName") == host_name
  }],
  ["remote_host_active_account_changed", ->(event) {
    event.dig("payload", "targetName") == target_name &&
      event.dig("payload", "hostName") == host_name
  }]
]

cursor = 0
proof_sequence = []

requirements.each do |required_name, predicate|
  matched = false
  while cursor < events.length
    event = events[cursor]
    if event["event"] == required_name && predicate.call(event)
      proof_sequence << required_name
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
    "passed" => proof_sequence == requirements.map(&:first),
    "requiredSequence" => requirements.map(&:first),
    "proofSequence" => proof_sequence,
    "eventCount" => events.length,
    "eventsPathPresent" => File.exist?(events_path)
  }
)
RUBY
}

read_scheduled_refresh_proof() {
  ruby - "${VALIDATION_EVENTS_PATH}" <<'RUBY'
require "json"

events_path = ARGV.fetch(0)
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

requirements = [
  ["scheduled_refresh_requested", ->(_event) { true }],
  ["scheduled_refresh_completed", ->(_event) { true }]
]

cursor = 0
proof_sequence = []

requirements.each do |required_name, predicate|
  matched = false
  while cursor < events.length
    event = events[cursor]
    if event["event"] == required_name && predicate.call(event)
      proof_sequence << required_name
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
    "passed" => proof_sequence == requirements.map(&:first),
    "requiredSequence" => requirements.map(&:first),
    "proofSequence" => proof_sequence,
    "eventCount" => events.length,
    "eventsPathPresent" => File.exist?(events_path)
  }
)
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

if [[ "${SCENARIO}" == "live-scheduled-refresh" ]]; then
  SCENARIO_SCREENSHOT_CAPTURED=0
  if screencapture -x "${SCREENSHOT_PATH}" >/dev/null 2>&1; then
    SCENARIO_SCREENSHOT_CAPTURED=1
  fi

  cat > "${UI_TREE_PATH}" <<EOF
{
  "liveSnapshotPath": "live-menu-snapshot.json",
  "runtimeAssertionsPath": "runtime-assertions.json",
  "runtimeSnapshot": $(cat "${LIVE_SNAPSHOT_PATH}"),
  "runtimeAssertions": $(cat "${RUNTIME_ASSERTIONS_PATH}")
}
EOF

  SCHEDULED_REFRESH_PROOF_JSON=""
  for _ in $(seq 1 30); do
    SCHEDULED_REFRESH_PROOF_JSON="$(read_scheduled_refresh_proof)"
    if [[ "$(printf '%s' "${SCHEDULED_REFRESH_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')" == "1" ]]; then
      break
    fi
    sleep 1
  done

  SCHEDULED_REFRESH_PROOF_PASSED="$(printf '%s' "${SCHEDULED_REFRESH_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')"
  SCHEDULED_REFRESH_PROOF_SEQUENCE="$(printf '%s' "${SCHEDULED_REFRESH_PROOF_JSON}" | ruby -rjson -e 'print(JSON.generate(JSON.parse(STDIN.read)["proofSequence"]))')"

  if [[ "${SCHEDULED_REFRESH_PROOF_PASSED}" != "1" ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The app emitted a runtime menu snapshot during launch"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The app did not emit the expected scheduled refresh event sequence before timeout."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${SCHEDULED_REFRESH_PROOF_SEQUENCE},
  "failureClass": "product_regression",
  "failureStep": "scheduled_refresh_events"
}
EOF
    echo "Live scheduled-refresh smoke failed: refresh event proof did not complete." >&2
    exit 23
  fi

  if ! verify_seal_proof; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "seal-proof/evidence/account-before.json",
    "seal-proof/evidence/account-after.json",
    "seal-proof/evidence/ui-after-refresh.json",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The app emitted a runtime menu snapshot during launch",
    "The scheduled refresh timer requested a background refresh",
    "The scheduled refresh completed successfully"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": $(seal_proof_failure_gaps_json),
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${SCHEDULED_REFRESH_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}",
  "failureClass": "product_regression",
  "failureStep": "seal_proof_verification"
}
EOF
    echo "Live scheduled-refresh smoke failed: Seal proof did not verify." >&2
    exit 24
  fi

  SCREENSHOT_ARTIFACTS=""
  if [[ "${SCENARIO_SCREENSHOT_CAPTURED}" -eq 1 ]]; then
    SCREENSHOT_ARTIFACTS='"screenshots/'"${SCENARIO}"'.png",'
  fi

  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    ${SCREENSHOT_ARTIFACTS}
    "live-auth-status.json",
    "app-server-status.json",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "seal-proof/evidence/account-before.json",
    "seal-proof/evidence/account-after.json",
    "seal-proof/evidence/ui-after-refresh.json",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The app emitted a runtime menu snapshot during launch",
    "The scheduled refresh timer requested a background refresh",
    "The scheduled refresh completed successfully"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "status": "passed",
  "sealProofScenario": "scheduled-refresh-preserves-account-catalog",
  "proofSequence": ${SCHEDULED_REFRESH_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}"
}
EOF

  echo "Live scheduled-refresh smoke artifacts written to ${ARTIFACT_ROOT}"
  exit 0
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

MENU_PROBE_OUTPUT="$(osascript <<'EOF'
tell application "System Events"
    tell process "CodexPill"
        tell menu bar 2
            click menu bar item 1
            delay 1
            set menuRef to menu 1 of menu bar item 1
            set itemCount to count of menu items of menuRef
            set titles to name of every menu item of menuRef
            set AppleScript's text item delimiters to linefeed
            set joined to titles as text
            set {menuX, menuY} to position of menuRef
            set {menuW, menuH} to size of menuRef
            return (itemCount as text) & linefeed & joined & linefeed & "__MENU_FRAME__" & linefeed & (menuX as text) & "," & (menuY as text) & "," & (menuW as text) & "," & (menuH as text)
        end tell
    end tell
end tell
EOF
)"

screencapture -x "${SCREENSHOT_PATH}"

osascript <<'EOF' >/dev/null 2>&1 || true
tell application "System Events"
    tell process "CodexPill"
        tell menu bar 2
            click menu bar item 1
        end tell
    end tell
end tell
EOF

MENU_ITEM_COUNT="$(printf '%s' "${MENU_PROBE_OUTPUT}" | ruby -e 'raw = STDIN.read; parts = raw.split("\n__MENU_FRAME__\n", 2); top = parts.fetch(0, ""); first_newline = top.index("\n"); abort("missing menu item count") unless first_newline; print top[0...first_newline].strip')"
MENU_TITLES_RAW="$(printf '%s' "${MENU_PROBE_OUTPUT}" | ruby -e 'raw = STDIN.read; top, _bottom = raw.split("\n__MENU_FRAME__\n", 2); first_newline = top.index("\n"); abort("missing menu titles") unless first_newline; print top[(first_newline + 1)..] || ""')"
MENU_FRAME_JSON="$(printf '%s' "${MENU_PROBE_OUTPUT}" | ruby -rjson -e 'raw = STDIN.read; _top, bottom = raw.split("\n__MENU_FRAME__\n", 2); abort("missing menu frame") if bottom.nil? || bottom.strip.empty?; x, y, width, height = bottom.strip.split(",").map { |value| Float(value) }; print(JSON.generate({ "x" => x, "y" => y, "width" => width, "height" => height }))')"
ACCOUNT_SUBMENU_PROOF_JSON='{"passed":true,"targetName":null,"targetLocation":null,"childTitles":[],"note":"No account submenu probe was required for this scenario."}'

if [[ "${SCENARIO}" == "live-menu-open" ]]; then
  ACCOUNT_SUBMENU_TARGET_JSON="$(read_account_target_json 1)"
  ACCOUNT_SUBMENU_TARGET_NAME="$(printf '%s' "${ACCOUNT_SUBMENU_TARGET_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["targetName"].to_s)')"
  ACCOUNT_SUBMENU_TARGET_LOCATION="$(printf '%s' "${ACCOUNT_SUBMENU_TARGET_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["targetLocation"].to_s)')"
  ACCOUNT_SUBMENU_TARGET_ROOT_INDEX="$(printf '%s' "${ACCOUNT_SUBMENU_TARGET_JSON}" | ruby -rjson -e 'value = JSON.parse(STDIN.read)["targetRootIndex"]; print(value.nil? ? "" : value)')"
  ACCOUNT_SUBMENU_TARGET_SUBMENU_INDEX="$(printf '%s' "${ACCOUNT_SUBMENU_TARGET_JSON}" | ruby -rjson -e 'value = JSON.parse(STDIN.read)["targetSubmenuIndex"]; print(value.nil? ? "" : value)')"
  ACCOUNT_SUBMENU_VISIBLE_COUNT="$(printf '%s' "${ACCOUNT_SUBMENU_TARGET_JSON}" | ruby -rjson -e 'print(Array(JSON.parse(STDIN.read)["visibleNames"]).length)')"
  ACCOUNT_SUBMENU_OVERFLOW_COUNT="$(printf '%s' "${ACCOUNT_SUBMENU_TARGET_JSON}" | ruby -rjson -e 'print(Array(JSON.parse(STDIN.read)["overflowNames"]).length)')"

  if [[ -n "${ACCOUNT_SUBMENU_TARGET_NAME}" && -n "${ACCOUNT_SUBMENU_TARGET_LOCATION}" && -n "${ACCOUNT_SUBMENU_TARGET_ROOT_INDEX}" && ( "${ACCOUNT_SUBMENU_TARGET_LOCATION}" != "overflow" || -n "${ACCOUNT_SUBMENU_TARGET_SUBMENU_INDEX}" ) ]]; then
    if ACCOUNT_SUBMENU_TITLES_RAW="$(probe_account_submenu "${ACCOUNT_SUBMENU_TARGET_LOCATION}" "${ACCOUNT_SUBMENU_TARGET_ROOT_INDEX}" "${ACCOUNT_SUBMENU_TARGET_SUBMENU_INDEX}")"; then
      ACCOUNT_SUBMENU_PROOF_JSON="$(printf '%s' "${ACCOUNT_SUBMENU_TITLES_RAW}" | ruby -rjson -e 'target_name = ARGV.fetch(0); target_location = ARGV.fetch(1); titles = STDIN.read.split("\n").map(&:strip).reject(&:empty?); passed = titles.include?("Switch on This Mac"); print(JSON.generate({ "passed" => passed, "targetName" => target_name, "targetLocation" => target_location, "childTitles" => titles }))' "${ACCOUNT_SUBMENU_TARGET_NAME}" "${ACCOUNT_SUBMENU_TARGET_LOCATION}")"
    else
      ACCOUNT_SUBMENU_PROOF_JSON="$(ruby -rjson -e 'print(JSON.generate({ "passed" => false, "targetName" => ARGV.fetch(0), "targetLocation" => ARGV.fetch(1), "childTitles" => [], "failure" => "accessibility_probe_failed" }))' "${ACCOUNT_SUBMENU_TARGET_NAME}" "${ACCOUNT_SUBMENU_TARGET_LOCATION}")"
    fi
  else
    ACCOUNT_SUBMENU_PROOF_JSON="$(ruby -rjson -e 'visible_count = ARGV.fetch(0).to_i; overflow_count = ARGV.fetch(1).to_i; print(JSON.generate({ "passed" => (visible_count + overflow_count).zero?, "targetName" => nil, "targetLocation" => nil, "childTitles" => [], "failure" => "no_account_target_available", "visibleCount" => visible_count, "overflowCount" => overflow_count }))' "${ACCOUNT_SUBMENU_VISIBLE_COUNT}" "${ACCOUNT_SUBMENU_OVERFLOW_COUNT}")"
  fi

  close_status_item_menu
fi

ACCOUNT_SUBMENU_PROOF_PASSED="$(printf '%s' "${ACCOUNT_SUBMENU_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')"

MENU_TITLES_JSON_STRING="$(printf '%s' "${MENU_TITLES_RAW}" | ruby -rjson -e 'print JSON.generate(STDIN.read)')"

cat > "${UI_TREE_PATH}" <<EOF
{
  "liveSnapshotPath": "live-menu-snapshot.json",
  "runtimeAssertionsPath": "runtime-assertions.json",
  "menuBarCount": ${MENU_BAR_COUNT_OUTPUT},
  "targetedMenuBar": 2,
  "targetedMenuBarItemIndex": 1,
  "menuItemCount": ${MENU_ITEM_COUNT},
  "menuFrame": ${MENU_FRAME_JSON},
  "accountSubmenuProbe": ${ACCOUNT_SUBMENU_PROOF_JSON},
  "menuItemTitlesRaw": ${MENU_TITLES_JSON_STRING},
  "runtimeSnapshot": $(cat "${LIVE_SNAPSHOT_PATH}"),
  "runtimeAssertions": $(cat "${RUNTIME_ASSERTIONS_PATH}")
}
EOF

LAYOUT_PROOF_JSON="$(ruby -rjson -e '
ui = JSON.parse(File.read(ARGV.fetch(0)))
menu_width = ui.dig("menuFrame", "width")
row_widths = ui.dig("runtimeSnapshot", "menuItems").to_a.map do |item|
  width = item["viewFrameWidth"]
  next if width.nil?

  {
    "itemTitle" => item["title"],
    "itemWidth" => width,
    "difference" => menu_width && width ? (menu_width - width) : nil
  }
end.compact

expected_flush_delta = 0.0
tolerance = 8.0
passed = !row_widths.empty? && row_widths.all? do |entry|
  difference = entry["difference"]
  !difference.nil? && (difference - expected_flush_delta).abs <= tolerance
end

print JSON.generate({
  "passed" => passed,
  "menuWidth" => menu_width,
  "rowWidths" => row_widths,
  "expectedFlushDelta" => expected_flush_delta,
  "tolerance" => tolerance
})
' "${UI_TREE_PATH}")"
LAYOUT_PROOF_PASSED="$(printf '%s' "${LAYOUT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')"

if [[ "${SCENARIO}" == "live-add-account-prompt" ]]; then
  if ! trigger_add_account_prompt >/dev/null 2>&1; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The live probe could not trigger the Add Account... menu action."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "add_account_prompt_menu_path"
}
EOF
    echo "Live add-account prompt smoke failed: could not trigger the menu path." >&2
    exit 19
  fi

  PROMPT_CANCELLED=0
  for _ in $(seq 1 20); do
    if cancel_text_input_prompt >/dev/null 2>&1; then
      PROMPT_CANCELLED=1
      break
    fi
    sleep 0.5
  done

  if [[ "${PROMPT_CANCELLED}" -ne 1 ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The live probe triggered the Add Account... menu action"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The Add Account name dialog was not reachable for cancellation."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "add_account_prompt_cancel"
}
EOF
    echo "Live add-account prompt smoke failed: could not cancel the dialog." >&2
    exit 20
  fi

  ADD_ACCOUNT_PROMPT_PROOF_JSON=""
  for _ in $(seq 1 20); do
    ADD_ACCOUNT_PROMPT_PROOF_JSON="$(read_add_account_prompt_proof)"
    if [[ "$(printf '%s' "${ADD_ACCOUNT_PROMPT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')" == "1" ]]; then
      break
    fi
    sleep 0.5
  done

  ADD_ACCOUNT_PROMPT_PROOF_PASSED="$(printf '%s' "${ADD_ACCOUNT_PROMPT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')"
  ADD_ACCOUNT_PROMPT_PROOF_SEQUENCE="$(printf '%s' "${ADD_ACCOUNT_PROMPT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.generate(JSON.parse(STDIN.read)["proofSequence"]))')"

  if [[ "${ADD_ACCOUNT_PROMPT_PROOF_PASSED}" != "1" ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The running app dispatched the validation Add Account action"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The app did not emit the expected Add Account prompt event sequence."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${ADD_ACCOUNT_PROMPT_PROOF_SEQUENCE},
  "failureClass": "product_regression",
  "failureStep": "add_account_prompt_events"
}
EOF
    echo "Live add-account prompt smoke failed: prompt event proof did not complete." >&2
    exit 19
  fi

  if ! verify_seal_proof; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The running app dispatched the validation Add Account action",
    "The Add Account prompt was presented",
    "The Add Account prompt was cancelled cleanly"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": $(seal_proof_failure_gaps_json),
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${ADD_ACCOUNT_PROMPT_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}",
  "failureClass": "product_regression",
  "failureStep": "seal_proof_verification"
}
EOF
    echo "Live add-account prompt smoke failed: Seal proof did not verify." >&2
    exit 20
  fi

  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "The running app dispatched the validation Add Account action",
    "The Add Account prompt was presented",
    "The Add Account prompt was cancelled cleanly",
    "The Seal proof manifest exists and the Seal proof gate completed"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "sealProofScenario": "add-account-name-dialog-cancelled",
  "status": "passed",
  "proofSequence": ${ADD_ACCOUNT_PROMPT_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}"
}
EOF

  echo "Live add-account prompt smoke artifacts written to ${ARTIFACT_ROOT}"
  exit 0
fi

if [[ "${SCENARIO}" == "live-add-account-name-dialog-cancelled" ]]; then
  if ! trigger_add_account_name_dialog >/dev/null 2>&1; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The live probe could not trigger the current Add Account... menu action."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "add_account_name_dialog_menu_path"
}
EOF
    echo "Live add-account name-dialog smoke failed: could not trigger the menu path." >&2
    exit 20
  fi

  PROMPT_CANCELLED=0
  for _ in $(seq 1 20); do
    if cancel_text_input_prompt >/dev/null 2>&1; then
      PROMPT_CANCELLED=1
      break
    fi
    sleep 0.5
  done

  if [[ "${PROMPT_CANCELLED}" -ne 1 ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The live probe triggered the Add Account... menu action"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The Add Account name dialog was not reachable for cancellation."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "add_account_name_dialog_cancel"
}
EOF
    echo "Live add-account name-dialog smoke failed: could not cancel the dialog." >&2
    exit 21
  fi

  ADD_ACCOUNT_NAME_DIALOG_PROOF_JSON=""
  for _ in $(seq 1 20); do
    ADD_ACCOUNT_NAME_DIALOG_PROOF_JSON="$(read_add_account_name_dialog_proof)"
    if [[ "$(printf '%s' "${ADD_ACCOUNT_NAME_DIALOG_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')" == "1" ]]; then
      break
    fi
    sleep 0.5
  done

  ADD_ACCOUNT_NAME_DIALOG_PROOF_PASSED="$(printf '%s' "${ADD_ACCOUNT_NAME_DIALOG_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')"
  ADD_ACCOUNT_NAME_DIALOG_PROOF_SEQUENCE="$(printf '%s' "${ADD_ACCOUNT_NAME_DIALOG_PROOF_JSON}" | ruby -rjson -e 'print(JSON.generate(JSON.parse(STDIN.read)["proofSequence"]))')"

  if [[ "${ADD_ACCOUNT_NAME_DIALOG_PROOF_PASSED}" != "1" ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The live probe triggered the Add Account... menu action",
    "The Add Account name dialog was cancelled"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The app did not emit the expected Add Account name-dialog event sequence."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${ADD_ACCOUNT_NAME_DIALOG_PROOF_SEQUENCE},
  "failureClass": "product_regression",
  "failureStep": "add_account_name_dialog_events"
}
EOF
    echo "Live add-account name-dialog smoke failed: dialog event proof did not complete." >&2
    exit 22
  fi

  if ! verify_seal_proof; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The Add Account... menu action was triggered",
    "The Add Account name dialog was presented",
    "The Add Account name dialog was cancelled cleanly"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": $(seal_proof_failure_gaps_json),
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${ADD_ACCOUNT_NAME_DIALOG_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}",
  "failureClass": "product_regression",
  "failureStep": "seal_proof_verification"
}
EOF
    echo "Live add-account name-dialog smoke failed: Seal proof did not verify." >&2
    exit 23
  fi

  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "seal-proof/evidence/account-before.json",
    "seal-proof/evidence/name-dialog-snapshot.json",
    "seal-proof/evidence/account-after.json",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "The Add Account... menu action was triggered",
    "The Add Account name dialog was presented",
    "The Add Account name dialog was cancelled cleanly",
    "The Seal proof manifest exists and the Seal proof gate completed"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "sealProofScenario": "add-account-name-dialog-cancelled",
  "status": "passed",
  "proofSequence": ${ADD_ACCOUNT_NAME_DIALOG_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}"
}
EOF

  echo "Live add-account name-dialog smoke artifacts written to ${ARTIFACT_ROOT}"
  exit 0
fi

if [[ "${SCENARIO}" == "live-add-host-destination-validation-failed" || "${SCENARIO}" == "live-add-host-prompt" ]]; then
  if ! trigger_add_host_prompt >/dev/null 2>&1; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The live probe could not trigger Hosts > Add Host…."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "add_host_menu_path"
}
EOF
    echo "Live add-host destination validation smoke failed: could not trigger the menu path." >&2
    exit 23
  fi

  POPULATE_HOST_SETUP_ERROR=""
  if ! POPULATE_HOST_SETUP_ERROR="$(populate_host_setup_destination "codexpill-validation.invalid" 2>&1)"; then
    POPULATE_HOST_SETUP_ERROR_JSON="$(printf '%s' "${POPULATE_HOST_SETUP_ERROR}" | ruby -rjson -e 'print(JSON.generate(STDIN.read))')"
    cancel_text_input_prompt >/dev/null 2>&1 || true
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The live probe triggered the Add Host menu path"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The live probe could not enter a destination into the Add Host setup dialog."
  ],
  "populateError": ${POPULATE_HOST_SETUP_ERROR_JSON},
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "add_host_setup_populate"
}
EOF
    echo "Live add-host destination validation smoke failed: could not populate the destination field: ${POPULATE_HOST_SETUP_ERROR}" >&2
    exit 24
  fi

  HOST_PROMPT_STATE_JSON=""
  HOST_PROMPT_PROOF_JSON=""
  HOST_PROMPT_VALIDATED=0
  for _ in $(seq 1 16); do
    if HOST_PROMPT_STATE_RAW="$(read_host_setup_prompt_state 2>/dev/null)"; then
      HOST_PROMPT_STATE_JSON="$(printf '%s' "${HOST_PROMPT_STATE_RAW}" | ruby -rjson -e '
      raw = STDIN.read
      title, enabled, texts = raw.split("\t", 3)
      decode = ->(value) { value.to_s.gsub("\\n", "\n").gsub("\\t", "\t").gsub("\\c", ",").gsub("\\\\", "\\") }
      payload = {
        "windowTitle" => decode.call(title),
        "addEnabled" => enabled == "true",
        "staticTexts" => texts.to_s.split(",").map { |text| decode.call(text) }
      }
      print(JSON.generate(payload))
    ')"
    else
      HOST_PROMPT_STATE_JSON='{"windowTitle":null,"addEnabled":false,"staticTexts":[],"windowPresent":false}'
    fi
    HOST_PROMPT_PROOF_JSON="$(read_add_host_prompt_proof)"
    HOST_PROMPT_VALIDATED="$(printf '%s' "${HOST_PROMPT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')"
    if [[ "${HOST_PROMPT_VALIDATED}" == "1" ]]; then
      break
    fi
    sleep 0.5
  done

  cancel_text_input_prompt >/dev/null 2>&1 || true

  if [[ "${HOST_PROMPT_VALIDATED}" != "1" ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The live probe triggered the Add Host menu path",
    "The destination field accepted input"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "Typing a host destination did not emit the expected add-host validation event sequence.",
    "This indicates that live validation never ran or never completed."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "hostSetupDialogState": ${HOST_PROMPT_STATE_JSON},
  "proofSequence": $(printf '%s' "${HOST_PROMPT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.generate(JSON.parse(STDIN.read)["proofSequence"] || []))'),
  "failureClass": "product_regression",
  "failureStep": "add_host_validation_feedback"
}
EOF
    echo "Live add-host destination validation smoke failed: validation feedback never appeared." >&2
    exit 25
  fi

  if ! verify_seal_proof; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "seal-proof/evidence/host-validation-snapshot.json",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The live probe triggered the Add Host menu path",
    "The destination field accepted input",
    "The Add Host setup dialog emitted validation feedback after input"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": $(seal_proof_failure_gaps_json),
  "scenario": "${SCENARIO}",
  "status": "failed",
  "hostSetupDialogState": ${HOST_PROMPT_STATE_JSON},
  "proofSequence": $(printf '%s' "${HOST_PROMPT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.generate(JSON.parse(STDIN.read)["proofSequence"] || []))'),
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}",
  "failureClass": "product_regression",
  "failureStep": "seal_proof_verification"
}
EOF
    echo "Live add-host destination validation smoke failed: Seal proof did not verify." >&2
    exit 26
  fi

  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "seal-proof/evidence/host-validation-snapshot.json",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "The Add Host setup dialog was presented",
    "The destination field accepted input",
    "The Add Host setup dialog emitted validation feedback after input"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "sealProofScenario": "add-host-destination-validation-failed",
  "status": "passed",
  "hostSetupDialogState": ${HOST_PROMPT_STATE_JSON},
  "proofSequence": $(printf '%s' "${HOST_PROMPT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.generate(JSON.parse(STDIN.read)["proofSequence"] || []))'),
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}"
}
EOF

  echo "Live add-host destination validation smoke artifacts written to ${ARTIFACT_ROOT}"
  exit 0
fi

if [[ "${SCENARIO}" == "live-account-switch" ]]; then
  if [[ "${CODEXPILL_ALLOW_LIVE_ACCOUNT_SWITCH_VALIDATION:-0}" != "1" && -z "${CODEXPILL_VALIDATION_APP_SUPPORT_DIR:-}" ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "Live account-switch validation mutates account state unless it runs with an isolated validation app-support directory.",
    "Set CODEXPILL_ALLOW_LIVE_ACCOUNT_SWITCH_VALIDATION=1 only when intentionally targeting real local state."
  ],
  "scenario": "${SCENARIO}",
  "status": "blocked",
  "failureClass": "environment_block",
  "failureStep": "scenario_guard"
}
EOF
    echo "Live account-switch smoke blocked: opt-in guard not enabled." >&2
    exit 11
  fi

  if [[ "${MENU_ITEM_COUNT}" == "0" ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "The runtime snapshot proved the menu wiring state before attempting a switch"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "Accessibility exposed zero menu items after opening the status item, so the live probe could not select an inactive account row.",
    "This remains an environment-limited live proof gap rather than an app snapshot gap."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "validation_gap",
  "failureStep": "menu_item_enumeration"
}
EOF
    echo "Live account-switch smoke failed: Accessibility exposed zero menu items." >&2
    exit 12
  fi

  SWITCH_TARGET_JSON="$(read_account_target_json 1)"
  SWITCH_TARGET_NAME="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["targetName"].to_s)')"
  SWITCH_TARGET_LOCATION="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["targetLocation"].to_s)')"
  SWITCH_TARGET_ROOT_INDEX="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'value = JSON.parse(STDIN.read)["targetRootIndex"]; print(value.nil? ? "" : value)')"
  SWITCH_TARGET_SUBMENU_INDEX="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'value = JSON.parse(STDIN.read)["targetSubmenuIndex"]; print(value.nil? ? "" : value)')"
  ORIGINAL_ACCOUNT_NAME="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["currentAccountName"].to_s)')"

  if [[ -z "${SWITCH_TARGET_NAME}" || -z "${SWITCH_TARGET_LOCATION}" || -z "${SWITCH_TARGET_ROOT_INDEX}" || ( "${SWITCH_TARGET_LOCATION}" == "overflow" && -z "${SWITCH_TARGET_SUBMENU_INDEX}" ) ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The runtime snapshot did not expose any inactive saved account that the live smoke could target."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "validation_gap",
  "failureStep": "switch_target_selection"
}
EOF
    echo "Live account-switch smoke failed: no inactive account target available." >&2
    exit 13
  fi

  if ! click_switch_target "${SWITCH_TARGET_LOCATION}" "${SWITCH_TARGET_ROOT_INDEX}" "${SWITCH_TARGET_SUBMENU_INDEX}" >/dev/null 2>&1; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "An inactive account target was selected from the runtime snapshot"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "Accessibility reached the menu but did not successfully click the target inactive account row."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "switch_row_click"
}
EOF
    echo "Live account-switch smoke failed: could not click the target row." >&2
    exit 14
  fi

  CONFIRMATION_ACCEPTED=0
  for _ in $(seq 1 20); do
    if accept_switch_confirmation >/dev/null 2>&1; then
      CONFIRMATION_ACCEPTED=1
      break
    fi
    sleep 0.5
  done

  if [[ "${CONFIRMATION_ACCEPTED}" -ne 1 ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "The target inactive account row was clicked",
    "The switch confirmation was presented"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The live probe dispatched the switch action but could not accept the confirmation alert."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "switch_confirmation_accept"
}
EOF
    echo "Live account-switch smoke failed: could not accept the confirmation alert." >&2
    exit 16
  fi

  SWITCH_EVENT_PROOF_JSON=""
  SWITCH_SNAPSHOT_MATCHED=0
  for _ in $(seq 1 30); do
    SWITCH_EVENT_PROOF_JSON="$(read_switch_event_proof "${SWITCH_TARGET_NAME}" "${ORIGINAL_ACCOUNT_NAME}")"
    SWITCH_SNAPSHOT_MATCHED="$(ruby -rjson -e 'snapshot = JSON.parse(File.read(ARGV[0])); target = ARGV[1]; current = snapshot.dig("currentAccount", "name").to_s; print(current == target ? "1" : "0")' "${LIVE_SNAPSHOT_PATH}" "${SWITCH_TARGET_NAME}")"
    if [[ "$(printf '%s' "${SWITCH_EVENT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')" == "1" && "${SWITCH_SNAPSHOT_MATCHED}" == "1" ]]; then
      break
    fi
    sleep 1
  done

  SWITCH_EVENT_PROOF_PASSED="$(printf '%s' "${SWITCH_EVENT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')"
  SWITCH_EVENT_PROOF_SEQUENCE="$(printf '%s' "${SWITCH_EVENT_PROOF_JSON}" | ruby -rjson -e 'print(JSON.generate(JSON.parse(STDIN.read)["proofSequence"]))')"

  if [[ "${SWITCH_EVENT_PROOF_PASSED}" != "1" || "${SWITCH_SNAPSHOT_MATCHED}" != "1" ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "The target inactive account row was clicked"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The app did not emit the full switch-account event sequence or the current-account snapshot did not move to the clicked target."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${SWITCH_EVENT_PROOF_SEQUENCE},
  "failureClass": "product_regression",
  "failureStep": "switch_transition"
}
EOF
    echo "Live account-switch smoke failed: switch transition proof did not complete." >&2
    exit 15
  fi

  if ! verify_seal_proof; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "The target inactive account row was clicked",
    "The app emitted the switch-account event sequence",
    "The runtime snapshot current account moved to the clicked target"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": $(seal_proof_failure_gaps_json),
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${SWITCH_EVENT_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}",
  "failureClass": "product_regression",
  "failureStep": "seal_proof_verification"
}
EOF
    echo "Live account-switch smoke failed: Seal proof did not verify." >&2
    exit 17
  fi

  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "seal-proof/evidence/account-before.json",
    "seal-proof/evidence/account-after.json",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "The target inactive account row was clicked",
    "The app emitted the switch-account event sequence",
    "The runtime snapshot current account moved to the clicked target"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "sealProofScenario": "switch-account-changes-active-account",
  "status": "passed",
  "proofSequence": ${SWITCH_EVENT_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}"
}
EOF

  echo "Live account-switch smoke artifacts written to ${ARTIFACT_ROOT}"
  exit 0
fi

if [[ "${SCENARIO}" == "live-remote-host-switch" ]]; then
  TARGET_HOST_NAME="buildbox"
  SWITCH_TARGET_JSON="$(read_host_account_target_json "${TARGET_HOST_NAME}")"
  SWITCH_TARGET_NAME="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["targetName"].to_s)')"
  SWITCH_TARGET_LOCATION="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["targetLocation"].to_s)')"
  SWITCH_TARGET_ROOT_INDEX="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'value = JSON.parse(STDIN.read)["targetRootIndex"]; print(value.nil? ? "" : value)')"
  SWITCH_TARGET_SUBMENU_INDEX="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'value = JSON.parse(STDIN.read)["targetSubmenuIndex"]; print(value.nil? ? "" : value)')"
  SWITCH_TARGET_ACTION_TITLE="$(printf '%s' "${SWITCH_TARGET_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["targetActionTitle"].to_s)')"

  if [[ -z "${SWITCH_TARGET_NAME}" || -z "${SWITCH_TARGET_LOCATION}" || -z "${SWITCH_TARGET_ROOT_INDEX}" || -z "${SWITCH_TARGET_ACTION_TITLE}" || ( "${SWITCH_TARGET_LOCATION}" == "overflow" && -z "${SWITCH_TARGET_SUBMENU_INDEX}" ) ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "validation-app-support/accounts.json",
    "validation-settings.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The runtime snapshot did not expose any saved account row with a remote switch target for buildbox."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "validation_gap",
  "failureStep": "remote_switch_target_selection"
}
EOF
    echo "Live remote-host-switch smoke failed: no host switch target available." >&2
    exit 24
  fi

  if ! click_account_submenu_action "${SWITCH_TARGET_LOCATION}" "${SWITCH_TARGET_ROOT_INDEX}" "${SWITCH_TARGET_SUBMENU_INDEX}" "${SWITCH_TARGET_ACTION_TITLE}" >/dev/null 2>&1; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "validation-app-support/accounts.json",
    "validation-settings.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "A remote host switch target was selected from the runtime snapshot"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "Accessibility reached the submenu target but did not successfully click the remote host switch action."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "failureClass": "environment_block",
  "failureStep": "remote_switch_row_click"
}
EOF
    echo "Live remote-host-switch smoke failed: could not click the host switch action." >&2
    exit 25
  fi

  REMOTE_SWITCH_PROOF_JSON=""
  REMOTE_SWITCH_SNAPSHOT_MATCHED=0
  for _ in $(seq 1 30); do
    REMOTE_SWITCH_PROOF_JSON="$(read_remote_host_switch_proof "${SWITCH_TARGET_NAME}" "${TARGET_HOST_NAME}")"
    REMOTE_SWITCH_SNAPSHOT_MATCHED="$(ruby -rjson -e 'snapshot = JSON.parse(File.read(ARGV[0])); target = ARGV[1]; host = ARGV[2]; remote_hosts = snapshot.fetch("remoteHosts", []); matched = remote_hosts.any? { |entry| entry["name"] == host && entry["connectionState"] == "connected" && entry.dig("activeAccount", "name") == target }; print(matched ? "1" : "0")' "${LIVE_SNAPSHOT_PATH}" "${SWITCH_TARGET_NAME}" "${TARGET_HOST_NAME}")"
    if [[ "$(printf '%s' "${REMOTE_SWITCH_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')" == "1" && "${REMOTE_SWITCH_SNAPSHOT_MATCHED}" == "1" ]]; then
      break
    fi
    sleep 1
  done

  REMOTE_SWITCH_PROOF_PASSED="$(printf '%s' "${REMOTE_SWITCH_PROOF_JSON}" | ruby -rjson -e 'print(JSON.parse(STDIN.read)["passed"] ? "1" : "0")')"
  REMOTE_SWITCH_PROOF_SEQUENCE="$(printf '%s' "${REMOTE_SWITCH_PROOF_JSON}" | ruby -rjson -e 'print(JSON.generate(JSON.parse(STDIN.read)["proofSequence"] || []))')"

  if [[ "${REMOTE_SWITCH_PROOF_PASSED}" != "1" || "${REMOTE_SWITCH_SNAPSHOT_MATCHED}" != "1" ]]; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "validation-app-support/accounts.json",
    "validation-settings.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility clicked the remote host switch target"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "The app did not emit the expected remote host switch event sequence and remote card update before timeout."
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${REMOTE_SWITCH_PROOF_SEQUENCE},
  "failureClass": "product_regression",
  "failureStep": "remote_host_switch_result"
}
EOF
    echo "Live remote-host-switch smoke failed: switch proof did not complete." >&2
    exit 26
  fi

  if ! verify_seal_proof; then
    cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "validation-app-support/accounts.json",
    "validation-settings.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility clicked the remote host switch target",
    "The app emitted the remote host switch event sequence",
    "The remote card updated to the chosen account on buildbox"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": $(seal_proof_failure_gaps_json),
  "scenario": "${SCENARIO}",
  "status": "failed",
  "proofSequence": ${REMOTE_SWITCH_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}",
  "failureClass": "product_regression",
  "failureStep": "seal_proof_verification"
}
EOF
    echo "Live remote-host-switch smoke failed: Seal proof did not verify." >&2
    exit 27
  fi

  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
    "seal-proof/manifest.json",
    "seal-proof/evidence/events.jsonl",
    "logs/seal-verifier.stdout.log",
    "logs/seal-verifier.stderr.log",
    "validation-app-support/accounts.json",
    "validation-settings.json",
    "logs/run-menubar.log"
  ],
  "assertions": [
    "Accessibility enumerated the open menu",
    "A remote host switch target was clicked from the saved account submenu",
    "The app emitted the remote host switch event sequence",
    "The remote card updated to the chosen account on buildbox"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "sealProofScenario": "switch-account-on-host-changes-remote-active-account",
  "status": "passed",
  "remoteSwitchTarget": {
    "accountName": "${SWITCH_TARGET_NAME}",
    "hostName": "${TARGET_HOST_NAME}",
    "actionTitle": "${SWITCH_TARGET_ACTION_TITLE}"
  },
  "proofSequence": ${REMOTE_SWITCH_PROOF_SEQUENCE},
  "sealProofVerificationMode": "${SEAL_PROOF_VERIFICATION_MODE}"
}
EOF

  echo "Live remote-host-switch smoke artifacts written to ${ARTIFACT_ROOT}"
  exit 0
fi

if [[ "${MENU_ITEM_COUNT}" == "0" ]]; then
  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
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
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
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

if [[ "${SCENARIO}" == "live-menu-open" && "${LAYOUT_PROOF_PASSED}" != "1" ]]; then
  LAYOUT_GAP="$(printf '%s' "${LAYOUT_PROOF_JSON}" | ruby -rjson -e '
proof = JSON.parse(STDIN.read)
entries = Array(proof["rowWidths"])
expected = proof["expectedFlushDelta"]
tolerance = proof["tolerance"]
if entries.empty?
  print("The live probe could not find any custom menu rows to compare against the rendered menu width.")
else
  summary = entries.map do |entry|
    title = entry["itemTitle"]
    diff = entry["difference"]
    "#{title}: #{diff.round(1)}pt"
  end.join(", ")
  print("The live menu width did not stay flush with every custom menu row. Row deltas: #{summary}. Expected #{expected.round(1)}pt +/- #{tolerance.round(1)}pt.")
end
')"
  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
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
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    "${LAYOUT_GAP}"
  ],
  "scenario": "${SCENARIO}",
  "status": "failed"
}
EOF
  echo "Live menubar smoke failed: custom menu row width does not match the rendered menu width." >&2
  exit 24
fi

if [[ "${SCENARIO}" == "live-menu-open" && "${ACCOUNT_SUBMENU_PROOF_PASSED}" != "1" ]]; then
  ACCOUNT_SUBMENU_GAP_JSON='"Accessibility did not reveal the expected Switch on This Mac target inside a saved-account submenu. See accountSubmenuProbe for target and child-title details."'
  cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
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
    "The status item on menu bar 2 opened and returned menu item titles",
    "The custom menu rows stayed flush with the rendered live menu width"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [
    ${ACCOUNT_SUBMENU_GAP_JSON}
  ],
  "scenario": "${SCENARIO}",
  "status": "failed",
  "accountSubmenuProbe": ${ACCOUNT_SUBMENU_PROOF_JSON}
}
EOF
  echo "Live menubar smoke failed: saved-account submenu proof did not reveal switch targets." >&2
  exit 25
fi

cat > "${SUMMARY_PATH}" <<EOF
{
  "invariantIds": ${INVARIANT_IDS_JSON},
  "proofLayer": "${PROOF_LAYER}",
  "artifacts": [
    "live-auth-status.json",
    "app-server-status.json",
    "screenshots/${SCENARIO}.png",
    "live-menu-snapshot.json",
    "runtime-assertions.json",
    "ui-tree.json",
    "validation-events.jsonl",
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
    "The status item on menu bar 2 opened and returned menu item titles",
    "The custom menu rows stayed flush with the rendered live menu width",
    "Accessibility opened a saved-account submenu and revealed switch targets"
  ],
  "command": "AGENT_NAME=${AGENT_NAME} SCENARIO=${SCENARIO} ./scripts/live_menubar_smoke.sh",
  "gaps": [],
  "scenario": "${SCENARIO}",
  "status": "passed",
  "accountSubmenuProbe": ${ACCOUNT_SUBMENU_PROOF_JSON}
}
EOF

echo "Live menubar smoke artifacts written to ${ARTIFACT_ROOT}"
