#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AGENT_NAME="${AGENT_NAME:-local}"
ARTIFACT_DIR="$ROOT_DIR/build/verification/mutation"
SUMMARY_PATH="$ARTIFACT_DIR/summary.md"
JSON_PATH="$ARTIFACT_DIR/muter-report.json"
PLAIN_PATH="$ARTIFACT_DIR/muter-report.txt"
MUTATED_COPY_DIR="${ROOT_DIR}_mutated"
MUTER_FILES=(
  "Sources/Core/Models/CodexRateLimits.swift"
  "Sources/Features/Accounts/Application/AccountActionFlow.swift"
  "Sources/Features/Accounts/Application/InactiveAccountAvailabilityRanking.swift"
  "Sources/Features/Hosts/Application/RemoteRateLimitResolution.swift"
)

write_summary_header() {
  mkdir -p "$ARTIFACT_DIR"
  {
    echo "# Mutation Testing Setup Report"
    echo
    echo "- Baseline test command: AGENT_NAME=$AGENT_NAME make test"
    echo "- Tool: Muter"
    echo "- Scope:"
    for source_file in "${MUTER_FILES[@]}"; do
      echo "  - $source_file"
    done
    echo "- Command: AGENT_NAME=$AGENT_NAME make mutation"
    echo "- Artifact directory: build/verification/mutation"
    echo "- Policy: report-only; no CI gate and no mutation score threshold"
  } > "$SUMMARY_PATH"
}

append_summary() {
  printf '%s\n' "$1" >> "$SUMMARY_PATH"
}

write_summary_header

if ! make test AGENT_NAME="$AGENT_NAME"; then
  append_summary "- Result: blocked before mutation"
  append_summary "- Blocker: baseline make test failed, so Muter was not run"
  echo "Baseline make test failed; mutation testing was not run. See $SUMMARY_PATH."
  exit 1
fi

if ! command -v muter >/dev/null 2>&1; then
  append_summary "- Result: blocked before mutation"
  append_summary "- Blocker: muter executable is not available on PATH"
  append_summary "- Recovery: install Muter, for example with Homebrew: brew install muter-mutation-testing/formulae/muter"
  echo "Muter is not available on PATH; mutation testing was not run. See $SUMMARY_PATH."
  exit 127
fi

TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

rm -f "$JSON_PATH" "$PLAIN_PATH"
if [[ -d "$MUTATED_COPY_DIR" ]]; then
  rm -rf "$MUTATED_COPY_DIR"
fi

MUTER_FILE_ARGS=()
for source_file in "${MUTER_FILES[@]}"; do
  MUTER_FILE_ARGS+=(--files-to-mutate "$source_file")
done

if muter run \
  --skip-update-check \
  "${MUTER_FILE_ARGS[@]}" \
  --format json \
  --output "$JSON_PATH"; then
  append_summary "- JSON report: build/verification/mutation/muter-report.json"
else
  append_summary "- Result: Muter JSON run failed"
  append_summary "- JSON report: build/verification/mutation/muter-report.json, if Muter created a partial report"
  echo "Muter JSON run failed. See $SUMMARY_PATH."
  exit 1
fi

ruby -rjson -e '
report_path, output_path = ARGV
report = JSON.parse(File.read(report_path))
files = report.fetch("fileReports")

lines = []
lines << "Muter mutation report"
lines << ""
lines << "Global score: #{report.fetch("globalMutationScore")}%"
lines << "Mutants introduced: #{report.fetch("totalAppliedMutationOperators")}"
lines << "Mutants killed: #{report.fetch("numberOfKilledMutants")}"
lines << "Runtime: #{report.fetch("timeElapsed")}"
lines << ""

files.each do |file_report|
  operators = file_report.fetch("appliedOperators")
  next if operators.empty?

  file_path = operators.first.fetch("mutationPoint").fetch("filePath")
  file_name = File.basename(file_path)
  killed = operators.count { |operator| operator.fetch("testSuiteOutcome") == "failed" }
  survived = operators.length - killed

  lines << "#{file_name}: #{operators.length} introduced, #{killed} killed, #{survived} survived"
  operators.each do |operator|
    point = operator.fetch("mutationPoint")
    position = point.fetch("position")
    outcome = operator.fetch("testSuiteOutcome") == "failed" ? "killed" : "survived"
    lines << "- #{outcome}: #{point.fetch("mutationOperatorId")} at #{file_name}:#{position.fetch("line")}:#{position.fetch("column")}"
  end
  lines << ""
end

File.write(output_path, lines.join("\n"))
' "$JSON_PATH" "$PLAIN_PATH"

append_summary "- Human-readable report: build/verification/mutation/muter-report.txt"
append_summary "- Result: completed"

echo "Mutation report written to $ARTIFACT_DIR."
