#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TIMEOUT_SECONDS="${TERRA_SWIFTPM_TIMEOUT_SECONDS:-180}"

terminate_tree() {
  local pid="$1"
  local child
  while read -r child; do
    [[ -z "$child" ]] && continue
    terminate_tree "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)
  kill "$pid" 2>/dev/null || true
}

diagnose_timeout() {
  local name="$1"
  echo "FAIL: $name did not finish within ${TIMEOUT_SECONDS}s." >&2
  echo "" >&2
  echo "Active SwiftPM/git dependency processes:" >&2
  ps -eo pid,ppid,etime,command \
    | rg 'swift-(build|test|package)|swift package|swift test|swift build|/\.build/checkouts/|git .*submodule|git .*clone|git-remote-https' \
    || true
  echo "" >&2
  echo "If this stalls at swift-protobuf, SwiftPM is cloning protobuf submodules." >&2
  echo "Re-run with a larger timeout via TERRA_SWIFTPM_TIMEOUT_SECONDS=600 if the network is slow." >&2
}

run_with_timeout() {
  local name="$1"
  shift

  echo "==> $name"
  "$@" &
  local pid="$!"
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= TIMEOUT_SECONDS )); then
      diagnose_timeout "$name"
      terminate_tree "$pid"
      wait "$pid" 2>/dev/null || true
      exit 124
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  wait "$pid"
}

run_with_timeout "SwiftPM manifest" swift package describe
run_with_timeout "SwiftPM dependency resolution" swift package resolve
run_with_timeout "Swift tests" swift test "$@"
