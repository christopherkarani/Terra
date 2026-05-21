#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Canonical docs/snippets must not reference removed/legacy front-facing names.
# NOTE: Migration and plan docs intentionally contain legacy names; exclude them.

RG_BASE=(
  rg
  --no-ignore-vcs
  --hidden
  --glob '!**/.build/**'
  --glob '!**/node_modules/**'
  --glob '!website/.next/**'
  --glob '!website/out/**'
  --glob '!Docs/plans/**'
  --glob '!Docs/reference/**'
  --glob '!Docs/Migration*.md'
  --glob '!Docs/API_V2_FLUENT_CALLSITE_SPEC.md'
  --glob '!Docs/Migration_v1_to_v2.md'
)

SCOPE=(
  README.md
  Docs/cookbook.md
  Docs/integrations.md
  Docs/Profiler-Integration.md
  Sources/TerraAutoInstrument/Terra.docc
  Examples
  website/src
)

PATTERNS=(
  'Terra\.trace\('
  'Terra\.agentic\('
  'Terra\.loop\('
  '\bTraceHandle\b'
  '\.attr\('
  '\.provider\('
  '\.includeContent\('
  '\bCaptureIntent\b'
  '\bOperationKind\b'
  '\.execute\b'
  'Terra\.inference\b'
  'Terra\.embedding\b'
  'Terra\.safetyCheck\b'
  'Terra\.(agent|tool)\(name:'
  'Terra\.(inference|stream|embedding)\(model:'
  '\b(InferenceCall|StreamingCall|EmbeddingCall|AgentCall|ToolCall|SafetyCheckCall)\b'
)

for path in "${SCOPE[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "FAIL: Legacy-reference validation path does not exist: $path" >&2
    exit 1
  fi
done

for pat in "${PATTERNS[@]}"; do
  if "${RG_BASE[@]}" -n -e "$pat" "${SCOPE[@]}"; then
    echo ""
    echo "FAIL: Found legacy reference pattern: $pat" >&2
    exit 1
  fi
done

echo "OK: No legacy references found in canonical docs/snippets."
