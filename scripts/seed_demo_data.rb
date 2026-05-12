#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

repo_root = File.expand_path("..", __dir__)
demo_root = File.join(repo_root, "build", "demo")
app_support_dir = File.join(demo_root, "CodexPillDemoAppSupport")
snapshots_dir = File.join(app_support_dir, "snapshots")
settings_path = File.join(demo_root, "codexpill-demo-settings.json")
manifest_path = File.join(demo_root, "manifest.json")

FileUtils.rm_rf(demo_root)
FileUtils.mkdir_p(snapshots_dir)

now = Time.utc(2026, 5, 11, 9, 0, 0)

def iso(time)
  time.utc.iso8601
end

def snapshot_payload(account_id:, user_id:, workspace_id:, email:, plan_type:)
  {
    "OPENAI_ACCOUNT_ID" => account_id,
    "tokens" => {
      "id_token" => {
        "email" => email,
        "https://api.openai.com/auth" => {
          "user_id" => user_id,
          "chatgpt_account_id" => workspace_id
        }
      }
    },
    "demo" => {
      "codexpill" => true,
      "plan_type" => plan_type,
      "note" => "Synthetic CodexPill demo data. Not a real Codex auth payload."
    }
  }
end

def rate_limits(plan_type:, session_used:, weekly_used:, session_resets_at:, weekly_resets_at:, fetched_at:)
  {
    "limitID" => nil,
    "limitName" => nil,
    "planType" => plan_type,
    "primary" => {
      "usedPercent" => session_used,
      "resetsAt" => iso(session_resets_at),
      "windowDurationMinutes" => 300
    },
    "secondary" => {
      "usedPercent" => weekly_used,
      "resetsAt" => iso(weekly_resets_at),
      "windowDurationMinutes" => 10_080
    },
    "fetchedAt" => iso(fetched_at)
  }
end

account_specs = [
  {
    id: "11111111-1111-4111-8111-111111111111",
    name: "Personal",
    email: "personal@example.com",
    plan_type: "prolite",
    display_plan: "Pro x5",
    session_used: 12,
    weekly_used: 18,
    session_reset_hours: 3,
    weekly_reset_days: 4,
    account_id: "demo-personal",
    user_id: "user-demo-personal",
    workspace_id: "workspace-demo-personal"
  },
  {
    id: "22222222-2222-4222-8222-222222222222",
    name: "Studio",
    email: "studio@example.com",
    plan_type: "pro",
    display_plan: "Pro x20",
    session_used: 41,
    weekly_used: 54,
    session_reset_hours: 2,
    weekly_reset_days: 5,
    account_id: "demo-studio",
    user_id: "user-demo-studio",
    workspace_id: "workspace-demo-studio"
  },
  {
    id: "33333333-3333-4333-8333-333333333333",
    name: "Research",
    email: "research@example.com",
    plan_type: "plus",
    display_plan: "Plus",
    session_used: 7,
    weekly_used: 29,
    session_reset_hours: 4,
    weekly_reset_days: 6,
    account_id: "demo-research",
    user_id: "user-demo-research",
    workspace_id: "workspace-demo-research"
  },
  {
    id: "44444444-4444-4444-8444-444444444444",
    name: "Build Farm",
    email: "buildfarm@example.com",
    plan_type: "team",
    display_plan: "Team",
    session_used: 0,
    weekly_used: 67,
    session_reset_hours: 5,
    weekly_reset_days: 3,
    account_id: "demo-build-farm",
    user_id: "user-demo-build-farm",
    workspace_id: "workspace-demo-build-farm"
  },
  {
    id: "55555555-5555-4555-8555-555555555555",
    name: "Sandbox",
    email: "sandbox@example.com",
    plan_type: "free",
    display_plan: "Free",
    session_used: 84,
    weekly_used: 91,
    session_reset_hours: 1,
    weekly_reset_days: 2,
    account_id: "demo-sandbox",
    user_id: "user-demo-sandbox",
    workspace_id: "workspace-demo-sandbox"
  }
]

accounts = account_specs.each_with_index.map do |spec, index|
  snapshot_file_name = "#{spec.fetch(:name).downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")}.json"
  snapshot = snapshot_payload(
    account_id: spec.fetch(:account_id),
    user_id: spec.fetch(:user_id),
    workspace_id: spec.fetch(:workspace_id),
    email: spec.fetch(:email),
    plan_type: spec.fetch(:plan_type)
  )
  snapshot_data = JSON.pretty_generate(snapshot)
  File.write(File.join(snapshots_dir, snapshot_file_name), snapshot_data)
  snapshot_fingerprint = Digest::SHA256.hexdigest(snapshot_data)

  {
    "id" => spec.fetch(:id),
    "name" => spec.fetch(:name),
    "snapshotFileName" => snapshot_file_name,
    "createdAt" => iso(now - 86_400),
    "updatedAt" => iso(now - (90 + index * 45)),
    "email" => spec.fetch(:email),
    "planType" => spec.fetch(:plan_type),
    "rateLimits" => rate_limits(
      plan_type: spec.fetch(:plan_type),
      session_used: spec.fetch(:session_used),
      weekly_used: spec.fetch(:weekly_used),
      session_resets_at: now + (spec.fetch(:session_reset_hours) * 3_600),
      weekly_resets_at: now + (spec.fetch(:weekly_reset_days) * 86_400),
      fetched_at: now - (30 + index * 20)
    ),
    "identity" => {
      "stableAccountID" => spec.fetch(:account_id),
      "authPrincipalIdentity" => {
        "subject" => "auth0|#{spec.fetch(:user_id)}",
        "chatGPTUserID" => spec.fetch(:user_id)
      },
      "workspaceIdentity" => {
        "workspaceAccountID" => spec.fetch(:workspace_id),
        "workspaceLabel" => spec.fetch(:display_plan)
      },
      "snapshotFingerprint" => snapshot_fingerprint,
      "remoteIdentity" => {
        "normalizedEmailAddress" => spec.fetch(:email)
      }
    }
  }
end

File.write(File.join(app_support_dir, "accounts.json"), JSON.pretty_generate(accounts))

# Make Personal the active local account for the demo app by writing the same
# snapshot to the isolated validation auth file used by AppPaths.
personal_snapshot = File.read(File.join(snapshots_dir, accounts.fetch(0).fetch("snapshotFileName")))
File.write(File.join(app_support_dir, "auth.json"), personal_snapshot)

settings = {
  "remoteHostStates" => [
    {
      "host" => {
        "destination" => "demo@buildbox.example",
        "displayName" => "buildbox"
      },
      "installedAccountIDs" => [
        accounts.fetch(0).fetch("id"),
        accounts.fetch(1).fetch("id"),
        accounts.fetch(3).fetch("id")
      ],
      "desiredAccountID" => accounts.fetch(3).fetch("id"),
      "verifiedAccount" => accounts.fetch(3),
      "detectedAccountID" => nil,
      "verificationStatus" => "verified",
      "lastVerificationError" => nil
    },
    {
      "host" => {
        "destination" => "demo@studio-mac.example",
        "displayName" => "studio-mac"
      },
      "installedAccountIDs" => [
        accounts.fetch(0).fetch("id"),
        accounts.fetch(2).fetch("id")
      ],
      "desiredAccountID" => accounts.fetch(0).fetch("id"),
      "verifiedAccount" => accounts.fetch(0),
      "detectedAccountID" => nil,
      "verificationStatus" => "verified",
      "lastVerificationError" => nil
    }
  ]
}
File.write(settings_path, JSON.pretty_generate(settings))

manifest = {
  "appSupportDirectory" => app_support_dir,
  "settingsFixture" => settings_path,
  "activeLocalAccount" => accounts.fetch(0).fetch("name"),
  "accounts" => accounts.map { |account| account.slice("name", "email", "planType") },
  "hosts" => settings.fetch("remoteHostStates").map { |state| state.fetch("host") }
}
File.write(manifest_path, JSON.pretty_generate(manifest))

puts "Seeded CodexPill demo data:"
puts "  App support: #{app_support_dir}"
puts "  Settings:    #{settings_path}"
puts "  Manifest:    #{manifest_path}"
