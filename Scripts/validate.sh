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
bash -n Scripts/validate.sh Scripts/validate-swiftpm.sh Scripts/validate_no_legacy_refs.sh Scripts/build-libtera-android.sh
python3 Scripts/validate-doc-snippets.py

run_if_present "Telemetry schema" "Scripts/validate-telemetry-schema.py"
run_if_present "Binding conformance" "Scripts/validate-bindings.py"

if [[ -d .agents/skills ]]; then
  section "Project skill scripts"
  find .agents/skills -name '*.py' -print0 | xargs -0 python3 -c 'import ast, pathlib, sys; [compile(pathlib.Path(path).read_text(encoding="utf-8"), path, "exec", ast.PyCF_ONLY_AST) for path in sys.argv[1:]]'
fi

section "Python bindings"
python3 -m py_compile terra-python/terra.py
python3 -m unittest discover -s terra-python -p 'test*.py'

section "Zig core"
(
  cd zig-core
  zig build test --summary all
  zig build
  test -f zig-out/lib/libterra.a
)

section "C++ bindings"
cmake -S terra-cpp -B .build/terra-cpp \
  -DTERRA_LIB_PATH="$ROOT/zig-core/zig-out/lib/libterra.a"
cmake --build .build/terra-cpp
(
  cd .build/terra-cpp
  ctest --output-on-failure
)

section "Rust bindings"
(
  cd terra-rust
  TERRA_LIB_DIR="$ROOT/zig-core/zig-out/lib" cargo test -- --test-threads=1
  TERRA_LIB_DIR="$ROOT/zig-core/zig-out/lib" cargo package --allow-dirty
)

if [[ "$MODE" != "quick" ]]; then
  section "SwiftPM"
  Scripts/validate-swiftpm.sh "$@"
else
  section "SwiftPM manifest"
  Scripts/validate-swiftpm.sh --manifest-only
fi

section "Android bindings"
if [[ "$MODE" == "quick" ]]; then
  skip "Android Gradle checks are skipped in quick mode"
elif command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
  section "Android native libraries"
  bash Scripts/build-libtera-android.sh
  (
    cd terra-android
    ./gradlew test assembleRelease
  )
else
  skip "Android Gradle checks require a Java runtime"
fi

echo ""
echo "Validation complete."
