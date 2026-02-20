#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:a:h:h}"
OUTPUT_DIR="${TERRA_RC_OUTPUT_DIR:-$ROOT_DIR/Artifacts/rc-hardening/latest}"
mkdir -p "$OUTPUT_DIR"

RC_ENV_DIR="${TERRA_RC_ENV_DIR:-$OUTPUT_DIR/.rc-env}"
mkdir -p \
  "$RC_ENV_DIR/home" \
  "$RC_ENV_DIR/tmp" \
  "$RC_ENV_DIR/cache" \
  "$RC_ENV_DIR/clang-module-cache" \
  "$RC_ENV_DIR/swiftpm/configuration" \
  "$RC_ENV_DIR/swiftpm/security"

# Use deterministic writable paths for toolchain caches in CI and sandboxes.
export HOME="${TERRA_RC_HOME:-$RC_ENV_DIR/home}"
export TMPDIR="${TERRA_RC_TMPDIR:-$RC_ENV_DIR/tmp}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$RC_ENV_DIR/cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$RC_ENV_DIR/clang-module-cache}"
export SWIFTPM_CONFIGURATION_PATH="${SWIFTPM_CONFIGURATION_PATH:-$RC_ENV_DIR/swiftpm/configuration}"
export SWIFTPM_SECURITY_PATH="${SWIFTPM_SECURITY_PATH:-$RC_ENV_DIR/swiftpm/security}"
export TERRA_RC_OUTPUT_DIR="$OUTPUT_DIR"

SUMMARY_JSON="$OUTPUT_DIR/rc-hardening-summary.json"
SUMMARY_TXT="$OUTPUT_DIR/rc-hardening-summary.txt"
REPORT_MD="$ROOT_DIR/terra-v1-rc-hardening-report.md"

GIT_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

STEP_NAMES=()
STEP_REQUIRED=()
STEP_STATUS=()
STEP_DURATION=()
STEP_LOGS=()
STEP_NOTES=()
OVERALL_STATUS="pass"

is_truthy() {
  local value="${1:-0}"
  case "${value:l}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

record_step() {
  STEP_NAMES+=("$1")
  STEP_REQUIRED+=("$2")
  STEP_STATUS+=("$3")
  STEP_DURATION+=("$4")
  STEP_LOGS+=("$5")
  STEP_NOTES+=("$6")

  if [[ "$3" == "fail" && "$2" == "required" ]]; then
    OVERALL_STATUS="fail"
  fi
}

run_step() {
  local name="$1"
  local required="$2"
  local note="$3"
  shift 3

  local log_file="$OUTPUT_DIR/${name}.log"
  local start_ts
  start_ts="$(date +%s)"

  if "$@" >"$log_file" 2>&1; then
    local end_ts
    end_ts="$(date +%s)"
    local duration=$((end_ts - start_ts))
    record_step "$name" "$required" "pass" "$duration" "$log_file" "$note"
  else
    local end_ts
    end_ts="$(date +%s)"
    local duration=$((end_ts - start_ts))
    record_step "$name" "$required" "fail" "$duration" "$log_file" "$note"
  fi
}

skip_step() {
  local name="$1"
  local required="$2"
  local note="$3"
  local log_file="$OUTPUT_DIR/${name}.log"
  echo "SKIPPED: $note" >"$log_file"
  record_step "$name" "$required" "skipped" "0" "$log_file" "$note"
}

run_static_audits() {
  rg -n "terra.v1|terra.semantic.version" "$ROOT_DIR/Docs/TelemetryConvention/terra-v1.md"
  rg -n "status: \\.forbidden|status: \\.badRequest|HTTPStatus\\(code: 403|HTTPStatus\\(code: 400" \
    "$ROOT_DIR/Sources/TerraTraceKit/OTLPHTTPServer.swift"
}

render_summaries() {
  {
    echo "Terra RC Hardening Summary"
    echo "Generated (UTC): $GENERATED_AT"
    echo "Commit SHA: $GIT_SHA"
    echo "Overall: $OVERALL_STATUS"
    echo

    local idx=1
    while [[ $idx -le ${#STEP_NAMES[@]} ]]; do
      echo "[$idx] ${STEP_NAMES[$idx]} status=${STEP_STATUS[$idx]} required=${STEP_REQUIRED[$idx]} duration_s=${STEP_DURATION[$idx]}"
      echo "    note=${STEP_NOTES[$idx]}"
      echo "    log=${STEP_LOGS[$idx]}"
      idx=$((idx + 1))
    done
  } >"$SUMMARY_TXT"

  {
    echo "{"
    echo "  \"generated_at\": \"$GENERATED_AT\","
    echo "  \"commit_sha\": \"$GIT_SHA\","
    echo "  \"overall\": \"$OVERALL_STATUS\","
    echo "  \"steps\": ["

    local idx=1
    while [[ $idx -le ${#STEP_NAMES[@]} ]]; do
      local comma=","
      if [[ $idx -eq ${#STEP_NAMES[@]} ]]; then
        comma=""
      fi
      echo "    {"
      echo "      \"name\": \"${STEP_NAMES[$idx]}\","
      echo "      \"required\": \"${STEP_REQUIRED[$idx]}\","
      echo "      \"status\": \"${STEP_STATUS[$idx]}\","
      echo "      \"duration_seconds\": ${STEP_DURATION[$idx]},"
      echo "      \"log\": \"${STEP_LOGS[$idx]}\","
      echo "      \"note\": \"${STEP_NOTES[$idx]}\""
      echo "    }$comma"
      idx=$((idx + 1))
    done

    echo "  ]"
    echo "}"
  } >"$SUMMARY_JSON"
}

render_report() {
  local verdict="GO"
  if [[ "$OVERALL_STATUS" != "pass" ]]; then
    verdict="NO-GO"
  fi

  {
    echo "# Terra v1 RC Hardening Report"
    echo
    echo "## RC Metadata"
    echo "- Commit SHA: \`$GIT_SHA\`"
    echo "- Contract: \`terra.v1\`"
    echo "- Generated (UTC): \`$GENERATED_AT\`"
    echo "- Scope: Live runtime validation, perf gates, stress determinism, parser invariants, UI telemetry parity, fixture hygiene, and CI gate wiring."
    echo
    echo "## Gate Commands"
    echo '```bash'
    echo "TERRA_ENABLE_LIVE_PROVIDER_TESTS=1 swift test --filter LiveProviderIntegrationTests"
    echo "TERRA_ENABLE_PERF_GATES=1 swift test --filter TerraPerformanceGateTests"
    echo "TERRA_ENABLE_PERF_GATES=1 swift test --filter HTTPPerformanceGateTests"
    echo "TERRA_ENABLE_PERF_GATES=1 swift test --filter TraceMacAppPerformanceGateTests"
    echo "swift test --filter TerraCompliancePolicyTests.testConcurrentPolicySuppression_isDeterministicAcrossRepeatedRounds"
    echo "swift test --filter OTLPHTTPServerTests.testOTLPHTTPServerMixedConcurrentAllowRejectStressIsDeterministic"
    echo "swift test --filter 'AIResponseStreamParserTests|HTTPIntegrationTests'"
    echo "swift test --filter TerraV1FixtureTests"
    echo "./Scripts/rc_hardening.sh"
    echo '```'
    echo
    echo "## Artifact Paths"
    echo "- JSON summary: \`$SUMMARY_JSON\`"
    echo "- Text summary: \`$SUMMARY_TXT\`"
    echo "- Terra perf gate: \`$OUTPUT_DIR/terra-performance-gate.json\`"
    echo "- HTTP perf gate: \`$OUTPUT_DIR/http-performance-gate.json\`"
    echo "- TraceMacApp perf gate: \`$OUTPUT_DIR/tracemacapp-performance-gate.json\`"
    echo
    echo "## Latest RC Gate Run"
    echo "- Command: \`./Scripts/rc_hardening.sh\`"
    echo "- Result: \`Overall: $OVERALL_STATUS\`"
    echo "- Summary artifact: \`$SUMMARY_JSON\`"
    echo
    echo "## Step Outcomes"
    local idx=1
    while [[ $idx -le ${#STEP_NAMES[@]} ]]; do
      echo "- \`${STEP_NAMES[$idx]}\`: status=\`${STEP_STATUS[$idx]}\`, required=\`${STEP_REQUIRED[$idx]}\`, duration=\`${STEP_DURATION[$idx]}s\`"
      echo "  - note: ${STEP_NOTES[$idx]}"
      echo "  - log: \`${STEP_LOGS[$idx]}\`"
      idx=$((idx + 1))
    done
    echo
    echo "## Go / No-Go"
    if [[ "$verdict" == "GO" ]]; then
      echo "- Verdict: **GO**"
    else
      echo "- Verdict: **NO-GO**"
      echo "- Blocking required steps:"
      local block_idx=1
      while [[ $block_idx -le ${#STEP_NAMES[@]} ]]; do
        if [[ "${STEP_REQUIRED[$block_idx]}" == "required" && "${STEP_STATUS[$block_idx]}" == "fail" ]]; then
          echo "  - ${STEP_NAMES[$block_idx]}"
        fi
        block_idx=$((block_idx + 1))
      done
    fi
  } >"$REPORT_MD"
}

cd "$ROOT_DIR"

# 1) Optional live provider matrix (self-hosted / local only)
if is_truthy "${TERRA_ENABLE_LIVE_PROVIDER_TESTS:-0}"; then
  run_step \
    "live-provider-matrix" \
    "required" \
    "Runs live Ollama/LM Studio matrix; skips at test-case level when endpoints are unavailable." \
    env TERRA_ENABLE_LIVE_PROVIDER_TESTS=1 swift test --filter LiveProviderIntegrationTests
else
  skip_step \
    "live-provider-matrix" \
    "required" \
    "Live provider matrix disabled (set TERRA_ENABLE_LIVE_PROVIDER_TESTS=1 to execute)."
fi

# 2) Performance gates
run_step \
  "perf-terra" \
  "required" \
  "Runs Terra inference/streaming overhead gates (p50<=3%, p95<=7%)." \
  env TERRA_ENABLE_PERF_GATES=1 swift test --filter TerraPerformanceGateTests

run_step \
  "perf-http" \
  "required" \
  "Runs HTTP stream parser overhead gate (p50<=3%, p95<=7%)." \
  env TERRA_ENABLE_PERF_GATES=1 swift test --filter HTTPPerformanceGateTests

run_step \
  "perf-tracemacapp" \
  "required" \
  "Runs TraceMacApp timeline compaction/render-prep overhead gate (p50<=3%, p95<=7%)." \
  env TERRA_ENABLE_PERF_GATES=1 swift test --filter TraceMacAppPerformanceGateTests

# 3) Determinism + stress gates
run_step \
  "compliance-stress" \
  "required" \
  "Runs concurrent compliance suppression determinism stress." \
  swift test --filter TerraCompliancePolicyTests.testConcurrentPolicySuppression_isDeterministicAcrossRepeatedRounds

run_step \
  "otlp-reject-stress" \
  "required" \
  "Runs mixed allow/reject/schema OTLP stress and verifies deterministic 200/403/400 outcomes." \
  swift test --filter OTLPHTTPServerTests.testOTLPHTTPServerMixedConcurrentAllowRejectStressIsDeterministic

# 4) Stream invariant coverage
run_step \
  "stream-invariants" \
  "required" \
  "Runs parser + HTTP integration invariants for out-of-order timestamps and recovery." \
  swift test --filter "AIResponseStreamParserTests|HTTPIntegrationTests"

# 5) Fixture/resource hygiene
run_step \
  "fixture-hygiene" \
  "required" \
  "Runs TerraV1 fixture suite to validate schema/runtime fixture integrity and package resource wiring." \
  swift test --filter TerraV1FixtureTests

# 6) Static contract/reject audits
run_step \
  "static-audits" \
  "required" \
  "Verifies terra.v1 contract source and 403/400 reject semantics in OTLP server." \
  run_static_audits

render_summaries
render_report

cat "$SUMMARY_TXT"
echo
printf 'JSON summary: %s\n' "$SUMMARY_JSON"
printf 'Text summary: %s\n' "$SUMMARY_TXT"
printf 'Report: %s\n' "$REPORT_MD"

if [[ "$OVERALL_STATUS" == "fail" ]]; then
  exit 1
fi

exit 0
