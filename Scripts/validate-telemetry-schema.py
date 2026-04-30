#!/usr/bin/env python3
"""Validate Docs/telemetry-schema.json shape and duplicate telemetry keys."""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCHEMA = ROOT / "Docs" / "telemetry-schema.json"
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


def validate(path: Path) -> int:
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
  if len(argv) > 2:
    print("usage: validate-telemetry-schema.py [path]", file=sys.stderr)
    return 2

  path = Path(argv[1]).resolve() if len(argv) == 2 else DEFAULT_SCHEMA
  if not path.exists():
    print(f"FAIL: schema file does not exist: {path}", file=sys.stderr)
    return 1

  return validate(path)


if __name__ == "__main__":
  raise SystemExit(main(sys.argv))
