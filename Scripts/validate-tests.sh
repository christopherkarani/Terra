#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Building tests"
swift build --build-tests

python3 - <<'PY'
import pathlib
import re
import subprocess
import sys

root = pathlib.Path.cwd()
tests_root = root / "Tests"

xctest_classes = []
swift_suites = []

for path in tests_root.rglob("*.swift"):
    text = path.read_text()

    for match in re.finditer(r"class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase", text):
        name = match.group(1)
        if name not in xctest_classes:
            xctest_classes.append(name)

    for match in re.finditer(r'@Suite\(([^)\n]+)', text):
        args = match.group(1)
        name_match = re.search(r'"([^"]+)"', args)
        if not name_match:
            continue
        name = name_match.group(1)
        if name not in swift_suites:
            swift_suites.append(name)

def run(label: str) -> None:
    print(f"==> {label}", flush=True)
    completed = subprocess.run(
        ["swift", "test", "--skip-build", "--filter", label],
        cwd=root,
    )
    if completed.returncode != 0:
        sys.exit(completed.returncode)

for name in xctest_classes:
    run(name)

for name in swift_suites:
    run(name)

print("==> Validation complete")
PY
