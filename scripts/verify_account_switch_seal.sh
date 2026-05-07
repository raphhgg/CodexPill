#!/usr/bin/env zsh
set -euo pipefail

SCENARIO="${SCENARIO:-switch-account-changes-active-account}"
AGENT_NAME="${AGENT_NAME:-local}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-build/verification/${AGENT_NAME}/${SCENARIO}}"
SEAL_PACKAGE_PATH="${CODEXPILL_SEAL_PACKAGE_PATH:-../Seal}"
SEAL_COMMAND="${CODEXPILL_SEAL_COMMAND:-swift run --package-path ${SEAL_PACKAGE_PATH} seal}"
SUMMARY_PATH="${ARTIFACT_ROOT}/codexpill-summary.json"
COMMAND_PATH="${ARTIFACT_ROOT}/command.txt"

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

case "${ARTIFACT_ROOT}" in
  build/verification/*|./build/verification/*|"${REPO_ROOT}"/build/verification/*)
    ;;
  *)
    echo "Refusing to write Seal runtime validation artifacts outside build/verification: ${ARTIFACT_ROOT}" >&2
    exit 64
    ;;
esac

mkdir -p "${ARTIFACT_ROOT}"

# Quarantine stale CodexPill runtime output for this selected flow. A pass must
# come from the Seal runner artifacts created by this invocation.
ruby -rfileutils - "${ARTIFACT_ROOT}" <<'RUBY'
artifact_root = File.expand_path(ARGV.fetch(0))
allowed_root = File.expand_path("build/verification")
unless artifact_root == allowed_root || artifact_root.start_with?(allowed_root + File::SEPARATOR)
  warn "Refusing to clean outside build/verification: #{artifact_root}"
  exit 64
end

%w[proof reports adapter seal-proof validation-events.jsonl summary.json codexpill-summary.json].each do |relative_path|
  FileUtils.rm_rf(File.join(artifact_root, relative_path))
end
RUBY

mkdir -p "${ARTIFACT_ROOT}"

cat > "${COMMAND_PATH}" <<EOF
${SEAL_COMMAND} run --scenario ${SCENARIO} --output ${ARTIFACT_ROOT}
EOF

seal_parts_file="$(mktemp)"
trap 'rm -f "${seal_parts_file}"' EXIT
ruby -rshellwords -e 'Shellwords.split(ARGV.fetch(0)).each { |part| puts part }' "${SEAL_COMMAND}" > "${seal_parts_file}"

seal_command=()
while IFS= read -r seal_part; do
  seal_command+=("${seal_part}")
done < "${seal_parts_file}"

if [[ "${#seal_command[@]}" -eq 0 ]]; then
  echo "CODEXPILL_SEAL_COMMAND parsed to an empty command." >&2
  exit 64
fi

set +e
"${seal_command[@]}" run \
  --scenario "${SCENARIO}" \
  --output "${ARTIFACT_ROOT}"
seal_exit=$?
set -e

ruby -rjson - "${SUMMARY_PATH}" "${SCENARIO}" "${ARTIFACT_ROOT}" "${seal_exit}" <<'RUBY'
summary_path, scenario, artifact_root, seal_exit = ARGV

summary = {
  "scenario" => scenario,
  "summaryType" => "compatibility_pointer",
  "authoritativeRuntimeValidation" => "seal",
  "doesNotDefineIndependentVerdict" => true,
  "sealRunnerExitCode" => seal_exit.to_i,
  "authoritativeArtifacts" => {
    "proofManifest" => "proof/manifest.json",
    "resultJson" => "reports/result.json",
    "reportMarkdown" => "reports/report.md",
    "adapterDirectory" => "adapter/"
  },
  "legacyCodexPillRuntimeArtifacts" => {
    "validationEvents" => {
      "path" => "validation-events.jsonl",
      "authoritative" => false,
      "compatibilityOnly" => true
    },
    "legacySummary" => {
      "path" => "summary.json",
      "authoritative" => false,
      "compatibilityOnly" => true
    }
  }
}

result_path = File.join(artifact_root, "reports/result.json")
if File.exist?(result_path)
  summary["sealResultStatusPath"] = "reports/result.json"
else
  summary["sealArtifactGap"] = "Seal reports/result.json was not produced; inspect adapter/ and runner output."
end

File.write(summary_path, JSON.pretty_generate(summary) + "\n")
RUBY

exit "${seal_exit}"
