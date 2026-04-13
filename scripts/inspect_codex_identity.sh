#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
require "json"
require "base64"
require "open3"
require "time"

def decode_jwt_payload(token)
  payload = token.to_s.split(".")[1]
  return {} if payload.nil? || payload.empty?

  payload += "=" * ((4 - payload.length % 4) % 4)
  JSON.parse(Base64.urlsafe_decode64(payload))
rescue
  {}
end

def auth_summary_from_raw(raw)
  tokens = raw.fetch("tokens", {})
  payload = decode_jwt_payload(tokens["id_token"])
  auth = payload["https://api.openai.com/auth"] || {}

  {
    "email" => payload["email"],
    "sub" => payload["sub"],
    "sid" => payload["sid"],
    "auth_provider" => payload["auth_provider"],
    "account_id" => tokens["account_id"],
    "chatgpt_account_id" => auth["chatgpt_account_id"],
    "chatgpt_plan_type" => auth["chatgpt_plan_type"],
    "chatgpt_user_id" => auth["chatgpt_user_id"],
    "user_id" => auth["user_id"],
    "organizations" => Array(auth["organizations"]).map do |organization|
      organization.slice("id", "title", "is_default", "role")
    end,
    "groups" => auth["groups"],
  }
end

def read_live_app_server_summary
  requests = [
    {
      "method" => "initialize",
      "id" => 1,
      "params" => {
        "clientInfo" => {
          "name" => "codexpill-diagnostics",
          "version" => "0.1",
        },
        "capabilities" => {
          "experimentalApi" => true,
        },
      },
    },
    { "method" => "initialized", "params" => {} },
    { "method" => "account/read", "id" => 2, "params" => { "refreshToken" => false } },
    { "method" => "account/rateLimits/read", "id" => 3, "params" => {} },
  ]

  stdin, stdout, stderr, wait = Open3.popen3("/usr/bin/env", "codex", "app-server")
  requests.each { |request| stdin.write(JSON.generate(request) + "\n") }
  stdin.flush

  messages = []
  deadline = Time.now + 6
  while Time.now < deadline
    ready = IO.select([stdout], nil, nil, 0.5)
    next unless ready

    line = stdout.gets
    break if line.nil?

    begin
      messages << JSON.parse(line)
    rescue JSON::ParserError
    end

    break if messages.any? { |message| message["id"] == 3 }
  end

  stdin.close rescue nil
  Process.kill("TERM", wait.pid) rescue nil
  stderr.read rescue nil

  account = messages.find { |message| message["id"] == 2 }
  rate_limits = messages.find { |message| message["id"] == 3 }

  {
    "message_ids" => messages.map { |message| message["id"] || message["method"] },
    "account" => account&.dig("result", "account"),
    "rate_limits_keys" => rate_limits&.dig("result", "rateLimits")&.keys&.sort,
    "primary" => rate_limits&.dig("result", "rateLimits", "primary"),
    "secondary" => rate_limits&.dig("result", "rateLimits", "secondary"),
    "credits" => rate_limits&.dig("result", "rateLimits", "credits"),
  }
end

codex_home = File.expand_path("~/.codex")
live_auth_path = File.join(codex_home, "auth.json")
live_raw = JSON.parse(File.read(live_auth_path))

output = {
  "captured_at" => Time.now.utc.iso8601,
  "live_auth" => auth_summary_from_raw(live_raw),
  "app_server" => read_live_app_server_summary,
}

puts JSON.pretty_generate(output)
RUBY
