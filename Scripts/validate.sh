#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="full"
if [[ "${1:-}" == "--quick" || "${1:-}" == "--ci" ]]; then
  MODE="${1#--}"
  shift
fi

section() {
  echo ""
  echo "==> $1"
}

skip() {
  echo "SKIP: $1"
}

run_if_present() {
  local label="$1"
  local script="$2"
  shift 2
  if [[ -f "$script" ]]; then
    section "$label"
    "$script" "$@"
  else
    skip "$label ($script is not present)"
  fi
}

section "Repository hygiene"
bash Scripts/validate_no_legacy_refs.sh
bash -n Scripts/validate.sh Scripts/validate-swiftpm.sh Scripts/validate_no_legacy_refs.sh
python3 Scripts/validate-doc-snippets.py

run_if_present "Telemetry schema" "Scripts/validate-telemetry-schema.py"
run_if_present "Binding conformance" "Scripts/validate-bindings.py"

section "Python bindings"
python3 -m py_compile terra-python/terra.py

section "Zig core"
(
  cd zig-core
  zig build test --summary all
)

section "Rust bindings"
(
  cd terra-rust
  cargo test -- --test-threads=1
)

if [[ "$MODE" != "quick" ]]; then
  section "SwiftPM"
  Scripts/validate-swiftpm.sh "$@"
else
  section "SwiftPM manifest"
  swift package describe >/dev/null
fi

section "Android bindings"
if command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
  (
    cd terra-android
    ./gradlew test assembleRelease
  )
else
  skip "Android Gradle checks require a Java runtime"
fi

echo ""
echo "Validation complete."
