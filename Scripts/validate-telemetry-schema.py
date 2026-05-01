#!/usr/bin/env python3
"""Validate Docs/telemetry-schema.json shape and duplicate telemetry keys.

Also performs source-key drift detection: walks Sources/ for emitted
telemetry keys (terra.* and gen_ai.*) and verifies they're registered in
the schema. Surfaces unregistered keys with the first-seen source path.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCHEMA = ROOT / "Docs" / "telemetry-schema.json"
DEFAULT_FIXTURE_DIR = ROOT / "Fixtures" / "trace-golden"
DEFAULT_SOURCE_DIR = ROOT / "Sources"
REQUIRED_FIELDS = {
    "key",
    "type",
    "unit",
    "owner_module",
    "stability",
    "viewer_behavior",
    "examples",
}
DEFAULT_ALLOWED_TYPES = {"string", "int", "double", "bool", "event"}
DEFAULT_ALLOWED_STABILITY = {"stable", "experimental", "deprecated", "internal"}
FIXTURE_KEYS_REQUIRING_SCHEMA = (
    "terra.",
    "gen_ai.",
    "process.",
    "metal.",
    "resource.",
    "event.",
)

# Patterns that match telemetry-key-shaped strings inside Swift source files.
# Each pattern captures one group: the literal key name.
SOURCE_EMIT_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    # `setAttribute(key: "terra.foo")` — span attribute setter, literal key.
    ("setAttribute", re.compile(r'setAttribute\s*\(\s*key:\s*"([^"]+)"')),
    # `attributes["terra.foo"] = ...` — dict-style attribute assignment.
    ("attributes-subscript", re.compile(r'attributes\s*\[\s*"([^"]+)"\s*\]\s*=')),
    # `.attribute("terra.foo", ...)` — call-style attribute helper.
    ("attribute-call", re.compile(r'\.attribute\s*\(\s*"([^"]+)"')),
    # `.event("terra.foo")` — event name helper. Tracked separately so the
    # caller can decide if event-shaped names should round-trip through the
    # registry as `type: "event"` entries.
    ("event-call", re.compile(r'\.event\s*\(\s*"([^"]+)"')),
    # `static let foo = "terra.bar"` and similar string-literal constants
    # whose value matches the terra.*/gen_ai.* shape. The pattern captures
    # any quoted "terra.foo" / "gen_ai.foo" string, which lets us catch
    # constants declared in *+Constants.swift files even when they're never
    # directly referenced via the call-site patterns above.
    ("string-literal-constant", re.compile(r'"((?:terra|gen_ai)\.[a-z][^"]*)"')),
)

# Keys we deliberately treat as NOT attribute keys, even though they look
# like one. These are usually span names, event names, dispatch queue
# labels, or test-only identifiers that share the `terra.` / `gen_ai.`
# prefix without participating in the attribute registry. Each entry
# documents *why* it's excluded so future maintainers can reverse the
# call if the key starts being emitted as a real span attribute.
EXCLUDED_SOURCE_KEY_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    # ----- Span names (SpanNames in Terra+Constants.swift) -----
    # `gen_ai.inference`, `gen_ai.embeddings`, `gen_ai.agent`, `gen_ai.tool`
    # are OpenTelemetry GenAI semantic-convention span names, not attribute
    # keys.
    ("gen-ai-span-name-inference", re.compile(r"^gen_ai\.inference$")),
    ("gen-ai-span-name-embeddings", re.compile(r"^gen_ai\.embeddings$")),
    ("gen-ai-span-name-agent", re.compile(r"^gen_ai\.agent$")),
    ("gen-ai-span-name-tool", re.compile(r"^gen_ai\.tool$")),
    # `terra.coreml.model_load`, `terra.session`, `terra.safety_check` are
    # Terra span names from `SpanNames` — not attribute keys.
    ("coreml-model-load-span-name", re.compile(r"^terra\.coreml\.model_load$")),
    ("session-span-name", re.compile(r"^terra\.session$")),
    ("safety-check-span-name", re.compile(r"^terra\.safety_check$")),
    # `terra.test.span` and `terra.invalid.span` are synthetic span names
    # used by package-internal test seams (`Terra._testSpanHandle`,
    # `Terra._invalidSpanHandle`).
    ("test-span-name", re.compile(r"^terra\.test\.span$")),
    ("invalid-test-span-name", re.compile(r"^terra\.invalid\.span$")),
    # ----- Metric instrument names (MetricNames in Terra+Constants.swift) -----
    # Emitted via the metrics API, not as span attributes.
    ("metric-name-inference-count", re.compile(r"^terra\.inference\.count$")),
    ("metric-name-inference-duration", re.compile(r"^terra\.inference\.duration_ms$")),
    # ----- Event names (emitted via span.addEvent / TerraEvent.name) -----
    # Privacy-classifier and lifecycle event names whose lifecycle uses
    # the event API, not span-attribute API. Their attached attributes
    # are registered separately.
    ("event-name-thermal-transition", re.compile(r"^terra\.thermal\.transition$")),
    ("event-name-warning", re.compile(r"^terra\.warning$")),
    ("event-name-memory-sample", re.compile(r"^terra\.memory\.sample$")),
    ("event-name-memory-warning", re.compile(r"^terra\.memory\.warning$")),
    ("event-name-token-lifecycle", re.compile(r"^terra\.token\.lifecycle$")),
    ("event-name-stream-lifecycle", re.compile(r"^terra\.stream\.lifecycle$")),
    ("event-name-anomaly", re.compile(r"^terra\.anomaly$")),
    ("event-name-policy", re.compile(r"^terra\.policy$")),
    ("event-name-audit", re.compile(r"^terra\.audit$")),
    ("event-name-recommendation", re.compile(r"^terra\.recommendation$")),
    ("event-name-llama-layer-profile", re.compile(r"^terra\.llama\.layer\.profile$")),
    # ----- Internal infrastructure identifiers -----
    # Dispatch queue label declared in OTLPHTTPServer.swift; not a span
    # attribute or event name.
    ("dispatch-queue-label-otlp", re.compile(r"^terra\.trace\.otlp\.httpserver$")),
    # ErrorType marker string used by CoreMLInstrumentation when the
    # compute-plan capture exceeds its timeout budget. Surfaces as a
    # value, not as a key, on the `compute_plan.error_type` attribute.
    ("error-type-value-capture-timeout", re.compile(r"^terra\.coreml\.compute_plan\.capture_timeout$")),
)


def is_excluded_source_key(key: str) -> bool:
  """Return True when a literal key from Sources should not be required in the registry."""
  for _label, pattern in EXCLUDED_SOURCE_KEY_PATTERNS:
    if pattern.search(key):
      return True
  return False


def collect_emitted_keys(source_dir: Path) -> dict[str, Path]:
  """Walk source_dir and return a mapping of emitted telemetry key -> first-seen file.

  Only keys matching `terra.*` or `gen_ai.*` are returned. The mapping
  preserves the first source file in which each key was observed so the
  validator can produce actionable error messages.

  Strings that end with `.` are skipped — those are documented prefix
  matchers used for runtime classification (e.g. `key.hasPrefix("terra.hw.")`),
  not literal attribute keys. Strings that contain Swift interpolation
  syntax (`\\(...)`) are likewise skipped since they're templates rather
  than concrete keys.
  """
  emitted: dict[str, Path] = {}
  if not source_dir.is_dir():
    return emitted

  for swift_path in sorted(source_dir.rglob("*.swift")):
    try:
      text = swift_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
      continue
    for _label, pattern in SOURCE_EMIT_PATTERNS:
      for match in pattern.finditer(text):
        key = match.group(1)
        if not (key.startswith("terra.") or key.startswith("gen_ai.")):
          continue
        if key.endswith("."):
          # Prefix matcher (e.g. "terra.hw." used with hasPrefix), not a key.
          continue
        if "\\(" in key:
          # Swift string interpolation template, not a concrete key.
          continue
        if key not in emitted:
          emitted[key] = swift_path
  return emitted


def validate_source_drift(
  registry_by_key: dict[str, dict[str, Any]],
  errors: list[str],
  source_dir: Path = DEFAULT_SOURCE_DIR,
) -> None:
  """Surface telemetry keys emitted from Sources/ that aren't registered."""
  emitted = collect_emitted_keys(source_dir)
  if not emitted:
    return

  unregistered: list[tuple[str, Path]] = []
  for key, first_seen in emitted.items():
    if key in registry_by_key:
      continue
    if is_excluded_source_key(key):
      continue
    unregistered.append((key, first_seen))

  if not unregistered:
    return

  for key, first_seen in sorted(unregistered):
    try:
      relative = first_seen.relative_to(ROOT)
    except ValueError:
      relative = first_seen
    errors.append(
      f"telemetry key {key!r} is emitted from Sources/ but not registered in the schema "
      f"(first seen: {relative})"
    )


class DuplicateTrackingDict(dict[str, Any]):
  duplicate_keys: list[str] = []

  @classmethod
  def reset(cls) -> None:
    cls.duplicate_keys = []


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> DuplicateTrackingDict:
  seen: set[str] = set()
  result = DuplicateTrackingDict()
  for key, value in pairs:
    if key in seen:
      DuplicateTrackingDict.duplicate_keys.append(key)
    seen.add(key)
    result[key] = value
  return result


def load_schema(path: Path) -> Any:
  DuplicateTrackingDict.reset()
  try:
    with path.open("r", encoding="utf-8") as handle:
      return json.load(handle, object_pairs_hook=reject_duplicate_object_keys)
  except json.JSONDecodeError as error:
    print(f"FAIL: {path}: invalid JSON at line {error.lineno}, column {error.colno}: {error.msg}", file=sys.stderr)
    raise SystemExit(1) from error


def require_string(entry: dict[str, Any], field: str, index: int, errors: list[str]) -> None:
  value = entry.get(field)
  if not isinstance(value, str) or not value.strip():
    errors.append(f"registry[{index}] field '{field}' must be a non-empty string")


def value_matches_type(value: Any, expected_type: str) -> bool:
  if expected_type == "string" or expected_type == "event":
    return isinstance(value, str)
  if expected_type == "int":
    return isinstance(value, int) and not isinstance(value, bool)
  if expected_type == "double":
    return isinstance(value, (int, float)) and not isinstance(value, bool)
  if expected_type == "bool":
    return isinstance(value, bool)
  return False


def fixture_key_requires_schema(key: str) -> bool:
  return key.startswith(FIXTURE_KEYS_REQUIRING_SCHEMA)


def validate_registered_fixture_key(
  path: Path,
  owner: str,
  key: str,
  registry_by_key: dict[str, dict[str, Any]],
  errors: list[str],
) -> dict[str, Any] | None:
  schema_entry = registry_by_key.get(key)
  if schema_entry is None and fixture_key_requires_schema(key):
    errors.append(f"{path}: {owner} uses unknown telemetry key {key!r}")
  return schema_entry


def validate_plain_attribute_map(
  path: Path,
  owner: str,
  attributes: Any,
  registry_by_key: dict[str, dict[str, Any]],
  errors: list[str],
) -> None:
  if not isinstance(attributes, dict):
    errors.append(f"{path}: {owner} attributes must be an object")
    return

  for key in attributes.keys():
    if not isinstance(key, str) or not key:
      errors.append(f"{path}: {owner} has invalid attribute key")
      continue
    validate_registered_fixture_key(path, owner, key, registry_by_key, errors)


def validate_typed_attribute_map(
  path: Path,
  owner: str,
  attributes: Any,
  registry_by_key: dict[str, dict[str, Any]],
  errors: list[str],
) -> None:
  if not isinstance(attributes, dict):
    errors.append(f"{path}: {owner} attributes must be an object")
    return

  allowed_types = DEFAULT_ALLOWED_TYPES - {"event"}
  for key, typed_value in attributes.items():
    if not isinstance(key, str) or not key:
      errors.append(f"{path}: {owner} has invalid attribute key")
      continue
    if not isinstance(typed_value, dict):
      errors.append(f"{path}: {owner} attribute {key} must be a typed object")
      continue

    attr_type = typed_value.get("type")
    value = typed_value.get("value")
    if attr_type not in allowed_types:
      errors.append(f"{path}: {owner} attribute {key} has invalid type {attr_type!r}")
      continue
    if not value_matches_type(value, str(attr_type)):
      errors.append(f"{path}: {owner} attribute {key} value does not match {attr_type}")

    schema_entry = validate_registered_fixture_key(path, owner, key, registry_by_key, errors)
    if schema_entry is not None and schema_entry.get("type") != attr_type:
      errors.append(
        f"{path}: {owner} attribute {key} fixture type {attr_type!r} "
        f"does not match schema type {schema_entry.get('type')!r}"
      )


def validate_golden_fixtures(
  registry_by_key: dict[str, dict[str, Any]],
  errors: list[str],
  fixture_dir: Path = DEFAULT_FIXTURE_DIR,
) -> None:
  if not fixture_dir.is_dir():
    errors.append(f"{fixture_dir}: fixture directory is missing")
    return

  event_keys = {
    key for key, entry in registry_by_key.items()
    if entry.get("type") == "event"
  }

  for path in sorted(fixture_dir.glob("*.json")):
    try:
      payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
      errors.append(f"{path}: invalid JSON: {error}")
      continue

    spans = payload.get("spans")
    if not isinstance(spans, list):
      errors.append(f"{path}: spans must be an array")
      continue

    if "resource" in payload:
      validate_plain_attribute_map(
        path,
        "fixture resource",
        payload.get("resource", {}),
        registry_by_key,
        errors,
      )

    for span in spans:
      if not isinstance(span, dict):
        errors.append(f"{path}: each span must be an object")
        continue
      span_id = str(span.get("span_id"))
      if "resource" in span:
        validate_plain_attribute_map(
          path,
          f"span {span_id} resource",
          span.get("resource", {}),
          registry_by_key,
          errors,
        )
      validate_typed_attribute_map(
        path,
        f"span {span_id}",
        span.get("attributes", {}),
        registry_by_key,
        errors,
      )

      events = span.get("events", [])
      if not isinstance(events, list):
        errors.append(f"{path}: span {span_id} events must be an array")
        continue

      for event in events:
        if not isinstance(event, dict):
          errors.append(f"{path}: span {span_id} event must be an object")
          continue

        event_name = event.get("name")
        if not isinstance(event_name, str) or not event_name:
          errors.append(f"{path}: span {span_id} event needs a name")
        elif event_name.startswith("terra.") and event_name not in event_keys:
          errors.append(f"{path}: event {event_name!r} is not registered as a schema event")

        timestamp = event.get("time_unix_nano")
        if not isinstance(timestamp, int) or isinstance(timestamp, bool):
          errors.append(f"{path}: event {event_name!r} needs integer time_unix_nano")

        validate_typed_attribute_map(
          path,
          f"event {event_name!r}",
          event.get("attributes", {}),
          registry_by_key,
          errors,
        )


def validate(path: Path, fixture_dir: Path = DEFAULT_FIXTURE_DIR) -> int:
  schema = load_schema(path)
  errors: list[str] = []

  for key in DuplicateTrackingDict.duplicate_keys:
    errors.append(f"duplicate JSON object key: {key}")

  if not isinstance(schema, dict):
    errors.append("top-level schema must be a JSON object")
    return report(errors)

  registry = schema.get("registry")
  if not isinstance(registry, list):
    errors.append("top-level field 'registry' must be a list")
    return report(errors)

  declared_required = schema.get("entry_required_fields", sorted(REQUIRED_FIELDS))
  if not isinstance(declared_required, list) or set(declared_required) != REQUIRED_FIELDS:
    errors.append(
      "entry_required_fields must list exactly: "
      + ", ".join(sorted(REQUIRED_FIELDS))
    )

  allowed_types = schema.get("allowed_types", sorted(DEFAULT_ALLOWED_TYPES))
  if not isinstance(allowed_types, list) or not all(isinstance(item, str) for item in allowed_types):
    errors.append("allowed_types must be a list of strings")
    allowed_type_set = DEFAULT_ALLOWED_TYPES
  else:
    allowed_type_set = set(allowed_types)

  allowed_stability = schema.get("allowed_stability", sorted(DEFAULT_ALLOWED_STABILITY))
  if not isinstance(allowed_stability, list) or not all(isinstance(item, str) for item in allowed_stability):
    errors.append("allowed_stability must be a list of strings")
    allowed_stability_set = DEFAULT_ALLOWED_STABILITY
  else:
    allowed_stability_set = set(allowed_stability)

  keys: list[str] = []
  registry_by_key: dict[str, dict[str, Any]] = {}
  for index, entry in enumerate(registry):
    if not isinstance(entry, dict):
      errors.append(f"registry[{index}] must be an object")
      continue

    missing = sorted(REQUIRED_FIELDS - set(entry.keys()))
    if missing:
      errors.append(f"registry[{index}] missing required field(s): {', '.join(missing)}")

    for field in ("key", "type", "unit", "owner_module", "stability", "viewer_behavior"):
      if field in entry:
        require_string(entry, field, index, errors)

    key = entry.get("key")
    if isinstance(key, str) and key.strip():
      keys.append(key)
      registry_by_key[key] = entry
      if " " in key:
        errors.append(f"registry[{index}] key contains whitespace: {key}")
    elif "key" in entry:
      errors.append(f"registry[{index}] field 'key' must be a non-empty string")

    entry_type = entry.get("type")
    if isinstance(entry_type, str) and entry_type not in allowed_type_set:
      errors.append(f"registry[{index}] has unsupported type '{entry_type}' for key '{key}'")

    stability = entry.get("stability")
    if isinstance(stability, str) and stability not in allowed_stability_set:
      errors.append(f"registry[{index}] has unsupported stability '{stability}' for key '{key}'")

    examples = entry.get("examples")
    if "examples" in entry and (not isinstance(examples, list) or len(examples) == 0):
      errors.append(f"registry[{index}] field 'examples' must be a non-empty list")

  duplicates = sorted(key for key, count in Counter(keys).items() if count > 1)
  for key in duplicates:
    errors.append(f"duplicate telemetry registry key: {key}")

  validate_golden_fixtures(registry_by_key, errors, fixture_dir=fixture_dir)
  validate_source_drift(registry_by_key, errors)

  return report(errors, checked_count=len(registry))


def report(errors: list[str], checked_count: int | None = None) -> int:
  if errors:
    for error in errors:
      print(f"FAIL: {error}", file=sys.stderr)
    return 1

  suffix = f" ({checked_count} entries)" if checked_count is not None else ""
  print(f"OK: telemetry schema is valid{suffix}.")
  return 0


def main(argv: list[str]) -> int:
  path = DEFAULT_SCHEMA
  fixture_dir = DEFAULT_FIXTURE_DIR
  schema_path_seen = False

  args = argv[1:]
  index = 0
  while index < len(args):
    arg = args[index]
    if arg == "--fixture-dir":
      index += 1
      if index >= len(args):
        print("usage: validate-telemetry-schema.py [path] [--fixture-dir path]", file=sys.stderr)
        return 2
      fixture_dir = Path(args[index]).resolve()
    elif arg.startswith("-"):
      print("usage: validate-telemetry-schema.py [path] [--fixture-dir path]", file=sys.stderr)
      return 2
    elif schema_path_seen:
      print("usage: validate-telemetry-schema.py [path] [--fixture-dir path]", file=sys.stderr)
      return 2
    else:
      path = Path(arg).resolve()
      schema_path_seen = True
    index += 1

  if not path.exists():
    print(f"FAIL: schema file does not exist: {path}", file=sys.stderr)
    return 1

  return validate(path, fixture_dir=fixture_dir)


if __name__ == "__main__":
  raise SystemExit(main(sys.argv))
