# Claude Usage

## User Story

As a CodexPill user who also works in Claude Code on a Pro or Max plan, I want to see my Claude 5-hour session and weekly limits next to my Codex limits, so I can pick the tool with headroom without opening Claude Code's `/usage` screen.

## Product Contract

Claude Usage is an optional, read-only, local-first feature. CodexPill shows the Claude subscription limit windows that Claude Code already reports to its own status line. CodexPill does not switch Claude accounts, sign in to Claude, or contact any Anthropic service.

The feature has one setup step that changes a file outside CodexPill: it points Claude Code's `statusLine.command` at a small relay script. CodexPill must ask for consent before it writes, with the exact change one click away, and it must offer an uninstall that restores the previous status line.

Claude usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

## Source Contract

The source is Claude Code's documented status line input (<https://code.claude.com/docs/en/statusline>, read 2026-10-09). Claude Code runs the configured command with session JSON on stdin. For claude.ai Pro and Max subscribers, after the session's first API response, that JSON includes:

- `rate_limits.five_hour.used_percentage` and `rate_limits.five_hour.resets_at`;
- `rate_limits.seven_day.used_percentage` and `rate_limits.seven_day.resets_at`.

`used_percentage` runs from 0 to 100. `resets_at` is Unix epoch seconds. Either window can be absent. Claude Code re-runs the status line when a new assistant message arrives and when a window it last reported reaches `resets_at`.

CodexPill must not use Anthropic's undocumented OAuth usage endpoint, the `Claude Code-credentials` Keychain item, `~/.claude/.credentials.json`, browser cookies, hidden WebViews, or terminal scraping of the Claude CLI.

All knowledge of the status line payload and of `~/.claude/settings.json` lives in `Sources/Platform/Claude`. Feature and UI code consume parsed values only.

## How It Works

1. Claude Code runs `codexpill-claude-usage-relay.sh` as its status line command, with the user's previous command as the relay's only argument.
2. The relay copies the two window values into `~/Library/Application Support/CodexPill/claude-usage.json` with a capture timestamp. It writes a temporary file and renames it, with owner-only permissions.
3. The relay passes the unchanged stdin to the previous command and prints its output and exit status unchanged. If the CodexPill write fails, the status line still behaves as before.
4. CodexPill reads the snapshot file and evaluates it against the current time. It treats Claude Code as connected only while `statusLine.command` runs the CodexPill relay.
5. `ClaudeCodeUsage` maps the snapshot onto the shared usage model: the 5-hour window becomes `Session`, the 7-day window becomes `Weekly`, and the capture time becomes the fetch time. Claude has no plan name. Because both files are small and local, CodexPill reads them on every menu refresh instead of on the 5-minute provider cadence.

The relay is a POSIX `sh` script that uses `/usr/bin/plutil` to read JSON. Both ship with macOS, so the relay needs no `jq`, Python, or Node. `/usr/bin/python3` was rejected because on a Mac without the Command Line Tools it opens an install prompt. A Swift helper binary was rejected for now because it needs a new build target and adds a signed executable for a job that takes four field reads.

The relay copy that Claude Code runs lives in `~/Library/Application Support/CodexPill/bin/`, not inside `CodexPill.app`, so the user's status line keeps working if the app is moved or deleted.

## Snapshot File

CodexPill owns this format:

```json
{"schema":1,"captured_at":1791565823,"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1760050000},"seven_day":{"used_percentage":18,"resets_at":1760500000}}}
```

The relay writes only allowlisted numeric fields. When Claude Code sends no `rate_limits`, the relay creates a file with `"rate_limits":{}` if none exists, and otherwise leaves the last good snapshot in place, so a new session's first status line run does not erase known limits.

When several Claude Code sessions run at once, the last one to update wins. They report the same subscription, so this is safe.

## States And Copy

The menu shows a `Claude Code` section below the saved accounts. It has no switching actions.

- **Not connected.** The status line does not run the relay. The section shows one `Connect Claude Code…` action.
- **Waiting for usage.** The relay is set up, but no snapshot exists yet or it has no windows. The user is not on Pro or Max, or no Claude Code session has received an API response since setup. Copy: `Waiting for Claude Code` / `Send a message in Claude Code to see usage.`
- **Current.** Windows present and captured within the freshness limit. `Session` and `Weekly` rows use the same meters, percent mode, layout, colors, and pacing markers as the Codex card, with `As of <time>` above them.
- **Stale.** Windows present but captured more than one hour ago. The rows are dimmed and the label still reads `As of <time>`.
- **Unreadable.** The file exists but does not parse. Copy: `Can't read Claude Code usage` / `Retrying soon.` CodexPill keeps the file untouched. Error messages never include file contents.

`<time>` is the time alone for today, otherwise the date and time. When connected, `Preferences` > `Disconnect Claude Code…` undoes the setup.

## Freshness Rules

- A window whose `resets_at` is in the past is shown as reset: 0% used and no reset time, until Claude Code reports a new window.
- Snapshot age is measured from `captured_at`. Older than one hour is stale.
- Claude Code updates the snapshot only while a session is active. Usage from claude.ai, the desktop app, or another Mac does not reach the relay, so an old snapshot can undercount. Stale tells the user that, and it never hides the values.

## Consent, Install, And Uninstall

Setup follows "a human step is one guided command": one `Connect Claude Code…` action asks for consent in one short alert:

> **Connect Claude Code?**
> CodexPill will add a small script to Claude Code's status line to read your usage limits. You can disconnect in Preferences.

A collapsed `Show Change` disclosure in the same alert reveals the settings path and the exact `statusLine` entry before and after the change, as the planner computes it. It shows only that entry, never the rest of `settings.json`, because the file can hold secrets in `env`. If `settings.json` changes between the alert and the write, CodexPill writes nothing and says so. On consent, CodexPill:

1. Copies the relay into its app-support `bin` folder with owner-only permissions.
2. Writes a one-time backup, `settings.json.codexpill-backup`, next to the settings file.
3. Sets `statusLine.type` to `command` and `statusLine.command` to the quoted relay path followed by the quoted previous command. Other keys, including `padding` and `refreshInterval`, stay as they were.

CodexPill honors `CLAUDE_CONFIG_DIR` from its own environment, and it writes through a symlinked `settings.json` instead of replacing the link. The settings file is rewritten with sorted keys, so key order can change. An isolated validation run (`CODEXPILL_VALIDATION_APP_SUPPORT_DIR`) uses `<isolated root>/.claude` unless `CLAUDE_CONFIG_DIR` is set, so it never edits the real `~/.claude`.

If a write fails, CodexPill shows `Could Not Update Claude Code` with one sentence for the cause, for example `CodexPill could not read Claude Code's settings, so nothing changed.`

`Disconnect Claude Code…` asks `Disconnect Claude Code?` / `CodexPill will restore your previous Claude Code status line.`, with the same `Show Change` disclosure, then restores the previous command, or removes the `statusLine` entry when there was none. It removes the relay copy and the saved `claude-usage.json`. If the user changed `statusLine.command` after setup, CodexPill no longer treats Claude Code as connected and leaves the setting alone.

The alert stays short, so these known effects live in this doc rather than in the alert:

- Users with no previous status line get a custom status line that prints nothing. Claude Code hides most footer keyboard hints whenever a custom status line is configured.
- `disableAllHooks` or a managed `allowManagedHooksOnly` policy stops the relay from running. CodexPill then stays in Not connected or Stale.
- Claude Code runs the status line only in trusted workspaces.

## Privacy

Only the two limit windows leave Claude Code. The relay never writes the working directory, transcript path, session ID, session name, model, cost, repository, pull request, prompt cache, or spend-limit fields. The relay holds the full payload in memory only long enough to extract four numbers and pass stdin to the previous command.

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- Relay tests run the real script with literal payloads and prove that no field other than the two windows is written, that stdin, stdout, and exit status pass through, and that a failed write does not change the status line.
- Reader tests cover every state above and the typed parse errors.
- Planner and installer tests cover install, re-install, uninstall round trips, preserved keys, symlinked settings, and refusal on invalid settings. They run against fixtures and temp directories, never the real `~/.claude/settings.json`.
- `ClaudeCodeUsageTests` map literal relay JSON to the shared usage model and run connect and disconnect against a temp `settings.json` with an existing status line, with none, and after the settings change under an open consent alert.
- A coordinator test walks the menu from `Connect Claude Code…` through declined consent, waiting, current, stale, and disconnect, reading the built `NSMenu`.

## Follow-Ups

- The relay writes to the real app-support path. An isolated validation run reads its own folder, so it must use a fixture snapshot file instead of the relay.
