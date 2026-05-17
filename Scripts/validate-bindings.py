#!/usr/bin/env python3
"""Validate Terra binding conformance without building SwiftPM dependencies."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]

CONTENT_CONSTANTS = {
    "never": 0,
    "opt_in": 1,
    "always": 2,
}

REDACTION_CONSTANTS = {
    "drop": 0,
    "length_only": 1,
    "hmac_sha256": 2,
    "sha256": 3,
}

SPAN_FEATURES = {
    "inference": {
        "C ABI": "terra_begin_inference_span_ctx",
        "Zig Core": "terra_begin_inference_span_ctx",
        "Rust": "begin_inference_span",
        "Python": "begin_inference_span",
        "Kotlin": "beginInferenceSpan",
        "C++": "begin_inference",
    },
    "embedding": {
        "C ABI": "terra_begin_embedding_span_ctx",
        "Zig Core": "terra_begin_embedding_span_ctx",
        "Rust": "begin_embedding_span",
        "Python": "begin_embedding_span",
        "Kotlin": "beginEmbeddingSpan",
        "C++": "begin_embedding",
    },
    "agent": {
        "C ABI": "terra_begin_agent_span_ctx",
        "Zig Core": "terra_begin_agent_span_ctx",
        "Rust": "begin_agent_span",
        "Python": "begin_agent_span",
        "Kotlin": "beginAgentSpan",
        "C++": "begin_agent",
    },
    "tool": {
        "C ABI": "terra_begin_tool_span_ctx",
        "Zig Core": "terra_begin_tool_span_ctx",
        "Rust": "begin_tool_span",
        "Python": "begin_tool_span",
        "Kotlin": "beginToolSpan",
        "C++": "begin_tool",
    },
    "safety": {
        "C ABI": "terra_begin_safety_span_ctx",
        "Zig Core": "terra_begin_safety_span_ctx",
        "Rust": "begin_safety_span",
        "Python": "begin_safety_span",
        "Kotlin": "beginSafetySpan",
        "C++": "begin_safety",
    },
    "streaming": {
        "C ABI": "terra_begin_streaming_span_ctx",
        "Zig Core": "terra_begin_streaming_span_ctx",
        "Rust": "begin_streaming_span",
        "Python": "begin_streaming_span",
        "Kotlin": "beginStreamingSpan",
        "C++": "begin_streaming",
    },
}

BINDING_FILES = {
    "C ABI": ["zig-core/include/terra.h"],
    "Zig Core": ["zig-core/src/c_api.zig", "zig-core/src/privacy.zig"],
    "Rust": ["terra-rust/src/ffi.rs", "terra-rust/src/error.rs", "terra-rust/src/lib.rs"],
    "Python": ["terra-python/terra.py"],
    "Kotlin": ["terra-android/kotlin/dev/terra/Terra.kt", "terra-android/kotlin/dev/terra/TerraConfig.kt", "terra-android/kotlin/dev/terra/TerraSpan.kt", "terra-android/kotlin/dev/terra/StreamingScope.kt"],
    "C++": ["terra-cpp/include/terra.hpp"],
}

VENDORED_LIBRARY = "Vendor/libtera.xcframework/macos-arm64_x86_64/libtera.a"

REQUIRED_VENDORED_SYMBOLS = {
    "_terra_transport_mqtt",
    "_terra_transport_coap",
    "_terra_transport_uart",
}

COMMON_FEATURES = {
    "config": {
        "C ABI": "terra_config_t",
        "Zig Core": "Config",
        "Rust": "TerraConfig",
        "Python": "TerraConfig",
        "Kotlin": "TerraConfig",
        "C++": "terra_config_t",
    },
    "context propagation": {
        "C ABI": "terra_span_context_t",
        "Zig Core": "SpanContext",
        "Rust": "SpanContext",
        "Python": "SpanContext",
        "Kotlin": "SpanContext",
        "C++": "SpanContext",
    },
    "string attribute": {
        "C ABI": "terra_span_set_string",
        "Zig Core": "terra_span_set_string",
        "Rust": "set_string",
        "Python": "set_string",
        "Kotlin": "setString",
        "C++": "void set(std::string_view key, std::string_view value)",
    },
    "int attribute": {
        "C ABI": "terra_span_set_int",
        "Zig Core": "terra_span_set_int",
        "Rust": "set_int",
        "Python": "set_int",
        "Kotlin": "setInt",
        "C++": "void set(std::string_view key, int64_t value)",
    },
    "double attribute": {
        "C ABI": "terra_span_set_double",
        "Zig Core": "terra_span_set_double",
        "Rust": "set_double",
        "Python": "set_double",
        "Kotlin": "setDouble",
        "C++": "void set(std::string_view key, double value)",
    },
    "bool attribute": {
        "C ABI": "terra_span_set_bool",
        "Zig Core": "terra_span_set_bool",
        "Rust": "set_bool",
        "Python": "set_bool",
        "Kotlin": "setBool",
        "C++": "void set(std::string_view key, bool value)",
    },
    "events": {
        "C ABI": "terra_span_add_event",
        "Zig Core": "terra_span_add_event",
        "Rust": "add_event",
        "Python": "add_event",
        "Kotlin": "addEvent",
        "C++": "add_event",
    },
    "status": {
        "C ABI": "terra_span_set_status",
        "Zig Core": "terra_span_set_status",
        "Rust": "set_status",
        "Python": "set_status",
        "Kotlin": "setStatus",
        "C++": "set_status",
    },
    "error recording": {
        "C ABI": "terra_span_record_error",
        "Zig Core": "terra_span_record_error",
        "Rust": "record_error",
        "Python": "record_error",
        "Kotlin": "recordError",
        "C++": "record_error",
    },
    "stream token": {
        "C ABI": "terra_streaming_record_token",
        "Zig Core": "terra_streaming_record_token",
        "Rust": "record_token",
        "Python": "record_token",
        "Kotlin": "recordToken",
        "C++": "record_token",
    },
    "stream first token": {
        "C ABI": "terra_streaming_record_first_token",
        "Zig Core": "terra_streaming_record_first_token",
        "Rust": "record_first_token",
        "Python": "record_first_token",
        "Kotlin": "recordFirstToken",
        "C++": "record_first_token",
    },
    "stream end": {
        "C ABI": "terra_streaming_end",
        "Zig Core": "terra_streaming_end",
        "Rust": "streaming_end",
        "Python": "finish_stream",
        "Kotlin": "finish",
        "C++": "finish_stream",
    },
    "diagnostics": {
        "C ABI": "terra_spans_dropped",
        "Zig Core": "terra_spans_dropped",
        "Rust": "spans_dropped",
        "Python": "spans_dropped",
        "Kotlin": "spansDropped",
        "C++": "spans_dropped",
    },
    "metrics": {
        "C ABI": "terra_record_inference_duration",
        "Zig Core": "terra_record_inference_duration",
        "Rust": "record_inference_duration",
        "Python": "record_inference_duration",
        "Kotlin": "recordInferenceDuration",
        "C++": "record_inference_duration",
    },
}


@dataclass(frozen=True)
class Finding:
    message: str


def read_text(relative_path: str) -> str:
    path = ROOT / relative_path
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise AssertionError(f"missing required file: {relative_path}") from None


def read_binding_text(binding: str) -> str:
    return "\n".join(read_text(path) for path in BINDING_FILES[binding])


def extract_c_defines_or_enum(text: str, names: dict[str, str]) -> dict[str, int]:
    values: dict[str, int] = {}
    for logical, symbol in names.items():
        match = re.search(rf"\b{re.escape(symbol)}\s*=\s*(\d+)", text)
        if match:
            values[logical] = int(match.group(1))
    return values


def extract_zig_enum(text: str, enum_name: str, names: dict[str, str]) -> dict[str, int]:
    match = re.search(rf"pub const {enum_name}\s*=\s*enum\(u8\)\s*\{{(?P<body>.*?)\}};", text, re.S)
    if not match:
        return {}
    body = match.group("body")
    values: dict[str, int] = {}
    for logical, symbol in names.items():
        found = re.search(rf"\b{re.escape(symbol)}\s*=\s*(\d+)", body)
        if found:
            values[logical] = int(found.group(1))
    return values


def extract_python_int_enum(text: str, class_name: str, names: dict[str, str]) -> dict[str, int]:
    match = re.search(rf"class {class_name}\(IntEnum\):(?P<body>.*?)(?:\n\nclass |\n\n# ──)", text, re.S)
    if not match:
        return {}
    body = match.group("body")
    values: dict[str, int] = {}
    for logical, symbol in names.items():
        found = re.search(rf"^\s*{re.escape(symbol)}\s*=\s*(\d+)", body, re.M)
        if found:
            values[logical] = int(found.group(1))
    return values


def extract_kotlin_enum(text: str, class_name: str, names: dict[str, str]) -> dict[str, int]:
    match = re.search(rf"enum class {class_name}[^\{{]*\{{(?P<body>.*?)\n\}}", text, re.S)
    if not match:
        return {}
    body = re.sub(r"/\*.*?\*/", "", match.group("body"), flags=re.S)
    body = re.sub(r"//.*", "", body)
    values: dict[str, int] = {}
    ordinal = 0
    for token in re.findall(r"^\s*([A-Z][A-Z0-9_]*)\b", body, re.M):
        for logical, symbol in names.items():
            if token == symbol and logical not in values:
                values[logical] = ordinal
                ordinal += 1
                break
        else:
            ordinal += 1
    return values


def extract_rust_ffi_constants(text: str, names: dict[str, str]) -> dict[str, int]:
    values: dict[str, int] = {}
    for logical, symbol in names.items():
        found = re.search(rf"\bpub const {re.escape(symbol)}:\s*c_int\s*=\s*(\d+);", text)
        if found:
            values[logical] = int(found.group(1))
    return values


def extract_cpp_constants(text: str, enum_name: str, names: dict[str, str]) -> dict[str, int]:
    match = re.search(rf"enum class {enum_name}[^\{{]*\{{(?P<body>.*?)\}};", text, re.S)
    if not match:
        return {}
    body = match.group("body")
    c_header = read_text("zig-core/include/terra.h")
    c_symbol_values = extract_c_defines_or_enum(
        c_header,
        {logical: c_symbol for logical, (_cpp_symbol, c_symbol) in names.items()},
    )
    values: dict[str, int] = {}
    for logical, (cpp_symbol, c_symbol) in names.items():
        found = re.search(rf"\b{re.escape(cpp_symbol)}\s*=\s*{re.escape(c_symbol)}", body)
        if found and logical in c_symbol_values:
            values[logical] = c_symbol_values[logical]
    return values


def compare_constants(
    label: str,
    actual: dict[str, int],
    expected: dict[str, int],
    findings: list[Finding],
    allow_missing: set[str] | None = None,
) -> None:
    allow_missing = allow_missing or set()
    for key, expected_value in expected.items():
        if key not in actual:
            if key not in allow_missing:
                findings.append(Finding(f"{label}: missing {key}={expected_value}"))
            continue
        if actual[key] != expected_value:
            findings.append(Finding(f"{label}: {key} is {actual[key]}, expected {expected_value}"))


def validate_constants(findings: list[Finding]) -> None:
    c_header = read_text("zig-core/include/terra.h")
    zig_privacy = read_text("zig-core/src/privacy.zig")
    rust_ffi = read_text("terra-rust/src/ffi.rs")
    python = read_text("terra-python/terra.py")
    kotlin = read_text("terra-android/kotlin/dev/terra/TerraConfig.kt")
    cpp = read_text("terra-cpp/include/terra.hpp")

    c_content = extract_c_defines_or_enum(
        c_header,
        {
            "never": "TERRA_CONTENT_NEVER",
            "opt_in": "TERRA_CONTENT_OPT_IN",
            "always": "TERRA_CONTENT_ALWAYS",
        },
    )
    c_redaction = extract_c_defines_or_enum(
        c_header,
        {
            "drop": "TERRA_REDACT_DROP",
            "length_only": "TERRA_REDACT_LENGTH_ONLY",
            "hmac_sha256": "TERRA_REDACT_HMAC_SHA256",
            "sha256": "TERRA_REDACT_SHA256",
        },
    )
    compare_constants("C content policy", c_content, CONTENT_CONSTANTS, findings)
    compare_constants("C redaction strategy", c_redaction, REDACTION_CONSTANTS, findings)

    compare_constants(
        "Zig content policy",
        extract_zig_enum(zig_privacy, "ContentPolicy", {"never": "never", "opt_in": "opt_in", "always": "always"}),
        CONTENT_CONSTANTS,
        findings,
    )
    compare_constants(
        "Zig redaction strategy",
        extract_zig_enum(
            zig_privacy,
            "RedactionStrategy",
            {"drop": "drop", "length_only": "length_only", "hmac_sha256": "hmac_sha256", "sha256": "sha256"},
        ),
        REDACTION_CONSTANTS,
        findings,
    )
    compare_constants(
        "Rust FFI content policy",
        extract_rust_ffi_constants(
            rust_ffi,
            {"never": "TERRA_CONTENT_NEVER", "opt_in": "TERRA_CONTENT_OPT_IN", "always": "TERRA_CONTENT_ALWAYS"},
        ),
        CONTENT_CONSTANTS,
        findings,
    )
    compare_constants(
        "Rust FFI redaction strategy",
        extract_rust_ffi_constants(
            rust_ffi,
            {
                "drop": "TERRA_REDACT_DROP",
                "length_only": "TERRA_REDACT_LENGTH_ONLY",
                "hmac_sha256": "TERRA_REDACT_HMAC_SHA256",
                "sha256": "TERRA_REDACT_SHA256",
            },
        ),
        REDACTION_CONSTANTS,
        findings,
    )
    compare_constants(
        "Python content policy",
        extract_python_int_enum(python, "ContentPolicy", {"never": "NEVER", "opt_in": "OPT_IN", "always": "ALWAYS"}),
        CONTENT_CONSTANTS,
        findings,
    )
    compare_constants(
        "Python redaction strategy",
        extract_python_int_enum(
            python,
            "RedactionStrategy",
            {"drop": "DROP", "length_only": "LENGTH_ONLY", "hmac_sha256": "HMAC_SHA256", "sha256": "SHA256"},
        ),
        REDACTION_CONSTANTS,
        findings,
    )
    compare_constants(
        "Kotlin content policy",
        extract_kotlin_enum(kotlin, "ContentPolicy", {"never": "NEVER", "opt_in": "OPT_IN", "always": "ALWAYS"}),
        CONTENT_CONSTANTS,
        findings,
    )
    compare_constants(
        "Kotlin redaction strategy",
        extract_kotlin_enum(
            kotlin,
            "RedactionStrategy",
            {"drop": "DROP", "length_only": "LENGTH_ONLY", "hmac_sha256": "HMAC_SHA256", "sha256": "SHA256"},
        ),
        REDACTION_CONSTANTS,
        findings,
    )
    compare_constants(
        "C++ content policy",
        extract_cpp_constants(
            cpp,
            "ContentPolicy",
            {
                "never": ("Never", "TERRA_CONTENT_NEVER"),
                "opt_in": ("OptIn", "TERRA_CONTENT_OPT_IN"),
                "always": ("Always", "TERRA_CONTENT_ALWAYS"),
            },
        ),
        CONTENT_CONSTANTS,
        findings,
    )
    compare_constants(
        "C++ redaction strategy",
        extract_cpp_constants(
            cpp,
            "RedactionStrategy",
            {
                "drop": ("Drop", "TERRA_REDACT_DROP"),
                "length_only": ("LengthOnly", "TERRA_REDACT_LENGTH_ONLY"),
                "hmac_sha256": ("HmacSha256", "TERRA_REDACT_HMAC_SHA256"),
                "sha256": ("Sha256", "TERRA_REDACT_SHA256"),
            },
        ),
        REDACTION_CONSTANTS,
        findings,
    )


def validate_header_parity(findings: list[Finding]) -> None:
    canonical = read_text("zig-core/include/terra.h")
    candidates = [
        "Sources/CTerraBridge/include/terra.h",
        "Vendor/libtera.xcframework/macos-arm64_x86_64/Headers/terra.h",
    ]
    for candidate in candidates:
        if read_text(candidate) != canonical:
            findings.append(Finding(f"{candidate}: header does not match zig-core/include/terra.h"))


def validate_vendored_symbols(findings: list[Finding]) -> None:
    library = ROOT / VENDORED_LIBRARY
    if not library.is_file():
        findings.append(Finding(f"{VENDORED_LIBRARY}: vendored static library is missing"))
        return

    nm = shutil.which("nm")
    if nm is None:
        findings.append(Finding("nm is required to validate vendored libtera symbols"))
        return

    result = subprocess.run(
        [nm, "-gU", str(library)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        findings.append(Finding(f"{VENDORED_LIBRARY}: nm failed: {result.stderr.strip()}"))
        return

    exported = set(re.findall(r"\b_terra_[A-Za-z0-9_]+\b", result.stdout))
    missing = sorted(REQUIRED_VENDORED_SYMBOLS - exported)
    if missing:
        findings.append(Finding(f"{VENDORED_LIBRARY}: missing exported symbols: {', '.join(missing)}"))


def feature_matrix() -> dict[str, dict[str, bool]]:
    all_features = {**SPAN_FEATURES, **COMMON_FEATURES}
    texts = {binding: read_binding_text(binding) for binding in BINDING_FILES}
    matrix: dict[str, dict[str, bool]] = {}
    for feature, tokens in sorted(all_features.items()):
        matrix[feature] = {}
        for binding, token in tokens.items():
            matrix[feature][binding] = token in texts[binding]
    return matrix


def validate_feature_matrix(findings: list[Finding]) -> dict[str, dict[str, bool]]:
    matrix = feature_matrix()
    required_bindings = set(BINDING_FILES)
    for feature, row in matrix.items():
        missing = sorted(binding for binding in required_bindings if not row.get(binding, False))
        if missing:
            findings.append(Finding(f"feature '{feature}' missing in: {', '.join(missing)}"))
    return matrix


def compact_source(text: str) -> str:
    return re.sub(r"\s+", "", text)


def validate_span_context_contract(findings: list[Finding]) -> None:
    checks = [
        ("Zig SpanContext validity", "zig-core/src/models.zig", "(self.trace_id_hi!=0orself.trace_id_lo!=0)andself.span_id!=0"),
        ("Zig parent filtering", "zig-core/src/terra.zig", "if(ctx.isValid())ctxelsenull"),
        ("Rust SpanContext validity", "terra-rust/src/lib.rs", "(self.trace_id_hi!=0||self.trace_id_lo!=0)&&self.span_id!=0"),
        ("Rust parent filtering", "terra-rust/src/lib.rs", "parent.filter(|ctx|ctx.is_valid())"),
        ("Python SpanContext validity", "terra-python/terra.py", "(self.trace_id_hi!=0orself.trace_id_lo!=0)andself.span_id!=0"),
        ("Python parent filtering", "terra-python/terra.py", "parentisNoneornotparent.is_valid"),
        ("Kotlin SpanContext validity", "terra-android/kotlin/dev/terra/SpanContext.kt", "(traceIdHi!=0L||traceIdLo!=0L)&&spanId!=0L"),
        ("Kotlin parent filtering", "terra-android/kotlin/dev/terra/Terra.kt", "this?.takeIf{it.isValid}"),
        ("C++ SpanContext validity", "terra-cpp/include/terra.hpp", "(trace_id_hi|trace_id_lo)!=0&&span_id!=0"),
        ("C++ parent filtering", "terra-cpp/include/terra.hpp", "parent_ctx&&parent_ctx->is_valid()"),
    ]
    for label, relative_path, needle in checks:
        if needle not in compact_source(read_text(relative_path)):
            findings.append(Finding(f"{label}: expected strict trace+span validity contract in {relative_path}"))


def require(condition: bool, findings: list[Finding], message: str) -> None:
    if not condition:
        findings.append(Finding(message))


def schema_event_keys() -> set[str]:
    path = ROOT / "Docs" / "telemetry-schema.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return set()
    registry = payload.get("registry", [])
    if not isinstance(registry, list):
        return set()
    return {
        entry["key"]
        for entry in registry
        if isinstance(entry, dict)
        and isinstance(entry.get("key"), str)
        and entry.get("type") == "event"
    }


def validate_attribute_map(path: Path, span_id: str, attributes: Any, findings: list[Finding]) -> None:
    require(isinstance(attributes, dict), findings, f"{path}: span {span_id} attributes must be an object")
    if not isinstance(attributes, dict):
        return
    valid_types = {
        "string": str,
        "int": int,
        "double": (int, float),
        "bool": bool,
    }
    for key, typed_value in attributes.items():
        require(isinstance(key, str) and key, findings, f"{path}: span {span_id} has invalid attribute key")
        require(isinstance(typed_value, dict), findings, f"{path}: attribute {key} must be typed object")
        if not isinstance(typed_value, dict):
            continue
        attr_type = typed_value.get("type")
        value = typed_value.get("value")
        require(attr_type in valid_types, findings, f"{path}: attribute {key} has invalid type {attr_type!r}")
        expected_type = valid_types.get(attr_type)
        if expected_type is not None:
            require(isinstance(value, expected_type), findings, f"{path}: attribute {key} value does not match {attr_type}")
            if attr_type == "int":
                require(not isinstance(value, bool), findings, f"{path}: attribute {key} int value must not be bool")
            if attr_type == "double":
                require(not isinstance(value, bool), findings, f"{path}: attribute {key} double value must not be bool")


def validate_golden_fixtures(findings: list[Finding]) -> None:
    fixture_dir = ROOT / "Fixtures" / "trace-golden"
    require(fixture_dir.is_dir(), findings, "Fixtures/trace-golden directory is missing")
    paths = sorted(fixture_dir.glob("*.json")) if fixture_dir.is_dir() else []
    require(bool(paths), findings, "Fixtures/trace-golden must contain at least one JSON fixture")
    required_kinds = {"workflow", "inference", "tool", "streaming"}
    registered_event_keys = schema_event_keys()

    for path in paths:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            findings.append(Finding(f"{path}: invalid JSON: {error}"))
            continue

        require(payload.get("schema_version") == "terra.trace.golden.v1", findings, f"{path}: unexpected schema_version")
        trace_id = payload.get("trace_id")
        require(isinstance(trace_id, str) and re.fullmatch(r"[0-9a-f]{32}", trace_id) is not None, findings, f"{path}: trace_id must be 32 lowercase hex chars")
        privacy = payload.get("privacy")
        require(isinstance(privacy, dict), findings, f"{path}: privacy must be present")
        if isinstance(privacy, dict):
            require(privacy.get("content_policy") in CONTENT_CONSTANTS, findings, f"{path}: privacy.content_policy is invalid")
            require(privacy.get("redaction_strategy") in REDACTION_CONSTANTS, findings, f"{path}: privacy.redaction_strategy is invalid")
            require(privacy.get("content_captured") is False, findings, f"{path}: golden fixtures must not capture raw content")

        spans = payload.get("spans")
        require(isinstance(spans, list) and spans, findings, f"{path}: spans must be a non-empty array")
        if not isinstance(spans, list):
            continue

        span_ids: set[str] = set()
        kinds: set[str] = set()
        for span in spans:
            require(isinstance(span, dict), findings, f"{path}: each span must be an object")
            if not isinstance(span, dict):
                continue
            span_id = span.get("span_id")
            parent_id = span.get("parent_span_id")
            kind = span.get("kind")
            status = span.get("status")
            start = span.get("start_time_unix_nano")
            end = span.get("end_time_unix_nano")
            require(isinstance(span_id, str) and re.fullmatch(r"[0-9a-f]{16}", span_id) is not None, findings, f"{path}: span_id must be 16 lowercase hex chars")
            if isinstance(span_id, str):
                require(span_id not in span_ids, findings, f"{path}: duplicate span_id {span_id}")
                span_ids.add(span_id)
            require(parent_id is None or (isinstance(parent_id, str) and re.fullmatch(r"[0-9a-f]{16}", parent_id) is not None), findings, f"{path}: parent_span_id must be null or 16 lowercase hex chars")
            require(kind in required_kinds, findings, f"{path}: span {span_id} has invalid kind {kind!r}")
            if isinstance(kind, str):
                kinds.add(kind)
            require(isinstance(span.get("name"), str) and span.get("name"), findings, f"{path}: span {span_id} needs a name")
            require(isinstance(start, int) and isinstance(end, int) and start <= end, findings, f"{path}: span {span_id} timestamps are invalid")
            require(isinstance(status, dict) and status.get("code") in {"unset", "ok", "error"}, findings, f"{path}: span {span_id} status is invalid")
            validate_attribute_map(path, str(span_id), span.get("attributes"), findings)
            events = span.get("events")
            require(isinstance(events, list), findings, f"{path}: span {span_id} events must be an array")
            if isinstance(events, list):
                for event in events:
                    require(isinstance(event, dict), findings, f"{path}: span {span_id} event must be object")
                    if isinstance(event, dict):
                        require(isinstance(event.get("name"), str) and event.get("name"), findings, f"{path}: span {span_id} event needs a name")
                        event_name = event.get("name")
                        require(
                            isinstance(event.get("time_unix_nano"), int) and not isinstance(event.get("time_unix_nano"), bool),
                            findings,
                            f"{path}: span {span_id} event {event_name!r} needs integer time_unix_nano",
                        )
                        if isinstance(event_name, str) and event_name.startswith("terra."):
                            require(event_name in registered_event_keys, findings, f"{path}: event {event_name!r} is not registered in telemetry schema")
                        validate_attribute_map(path, str(span_id), event.get("attributes", {}), findings)

        for span in spans:
            if isinstance(span, dict) and span.get("parent_span_id") is not None:
                require(span.get("parent_span_id") in span_ids, findings, f"{path}: span {span.get('span_id')} parent is missing")

        require(required_kinds.issubset(kinds), findings, f"{path}: must include workflow, inference, tool, and streaming spans")
        streaming_error = [
            span for span in spans
            if isinstance(span, dict)
            and span.get("kind") == "streaming"
            and isinstance(span.get("status"), dict)
            and span["status"].get("code") == "error"
        ]
        require(bool(streaming_error), findings, f"{path}: must include a streaming error span")
        for span in streaming_error:
            attrs = span.get("attributes", {})
            events = span.get("events", [])
            require("terra.stream.chunk_count" in attrs, findings, f"{path}: streaming error span needs chunk_count")
            require("terra.stream.output_tokens" in attrs, findings, f"{path}: streaming error span needs output_tokens")
            require(any(isinstance(event, dict) and event.get("name") == "exception" for event in events), findings, f"{path}: streaming error span needs exception event")


def print_matrix(matrix: dict[str, dict[str, bool]]) -> None:
    bindings = list(BINDING_FILES)
    print("Binding feature matrix:")
    print("feature," + ",".join(bindings))
    for feature in sorted(matrix):
        row = ["yes" if matrix[feature].get(binding) else "no" for binding in bindings]
        print(feature + "," + ",".join(row))


def main() -> int:
    findings: list[Finding] = []
    validate_constants(findings)
    validate_header_parity(findings)
    validate_vendored_symbols(findings)
    matrix = validate_feature_matrix(findings)
    validate_span_context_contract(findings)
    validate_golden_fixtures(findings)

    if "--matrix" in sys.argv:
        print_matrix(matrix)

    if findings:
        print("Binding validation failed:", file=sys.stderr)
        for finding in findings:
            print(f"- {finding.message}", file=sys.stderr)
        return 1

    print("Binding constants, feature matrix, and golden trace fixtures are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
