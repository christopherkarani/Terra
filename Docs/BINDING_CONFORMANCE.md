# Binding Conformance

This document records the binding surface validated by `Scripts/validate-bindings.py`.
The check is intentionally cheap: it reads source files and golden JSON fixtures without building SwiftPM dependencies or native libraries.

## Validation

```sh
python3 Scripts/validate-bindings.py
python3 Scripts/validate-bindings.py --matrix
```

The script validates:

- C ABI, Zig, Rust, Python, Kotlin, and C++ content-policy and redaction numeric values.
- Binding feature presence for span creation, attributes, events, status, errors, context propagation, streaming helpers, diagnostics, and metrics.
- Golden trace fixture shape under `Fixtures/trace-golden`.

## Redaction Constants

| Concept | Canonical value | C ABI | Zig | Rust FFI | Python | Kotlin | C++ |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| Content never | 0 | `TERRA_CONTENT_NEVER` | `never` | `TERRA_CONTENT_NEVER` | `NEVER` | `NEVER` | `Never` |
| Content opt-in | 1 | `TERRA_CONTENT_OPT_IN` | `opt_in` | `TERRA_CONTENT_OPT_IN` | `OPT_IN` | `OPT_IN` | `OptIn` |
| Content always | 2 | `TERRA_CONTENT_ALWAYS` | `always` | `TERRA_CONTENT_ALWAYS` | `ALWAYS` | `ALWAYS` | `Always` |
| Redact drop | 0 | `TERRA_REDACT_DROP` | `drop` | `TERRA_REDACT_DROP` | `DROP` | `DROP` | `Drop` |
| Redact length only | 1 | `TERRA_REDACT_LENGTH_ONLY` | `length_only` | `TERRA_REDACT_LENGTH_ONLY` | `LENGTH_ONLY` | `LENGTH_ONLY` | `LengthOnly` |
| Redact HMAC-SHA256 | 2 | `TERRA_REDACT_HMAC_SHA256` | `hmac_sha256` | `TERRA_REDACT_HMAC_SHA256` | `HMAC_SHA256` | `HMAC_SHA256` | `HmacSha256` |
| Redact SHA256 legacy | 3 | `TERRA_REDACT_SHA256` | `sha256` | `TERRA_REDACT_SHA256` | `SHA256` | `SHA256` | `Sha256` |

The validator fails on numeric drift and on missing binding symbols for these constants.

## Span Context Contract

All bindings treat `SpanContext` as valid only when it contains both:

- a non-zero trace ID (`trace_id_hi != 0 || trace_id_lo != 0`)
- a non-zero span ID (`span_id != 0`)

Invalid parent contexts are ignored at binding boundaries where practical and in the Zig core, so a partial context starts a new root span instead of propagating a broken trace.

## Binding Feature Matrix

| Feature | C ABI | Zig Core | Rust | Python | Kotlin | C++ |
| --- | --- | --- | --- | --- | --- | --- |
| Config | Yes | Yes | Yes | Yes | Yes | Yes |
| Context propagation | Yes | Yes | Yes | Yes | Yes | Yes |
| Inference span | Yes | Yes | Yes | Yes | Yes | Yes |
| Embedding span | Yes | Yes | Yes | Yes | Yes | Yes |
| Agent span | Yes | Yes | Yes | Yes | Yes | Yes |
| Tool span | Yes | Yes | Yes | Yes | Yes | Yes |
| Safety span | Yes | Yes | Yes | Yes | Yes | Yes |
| Streaming span | Yes | Yes | Yes | Yes | Yes | Yes |
| String attribute | Yes | Yes | Yes | Yes | Yes | Yes |
| Int attribute | Yes | Yes | Yes | Yes | Yes | Yes |
| Double attribute | Yes | Yes | Yes | Yes | Yes | Yes |
| Bool attribute | Yes | Yes | Yes | Yes | Yes | Yes |
| Events | Yes | Yes | Yes | Yes | Yes | Yes |
| Status | Yes | Yes | Yes | Yes | Yes | Yes |
| Error recording | Yes | Yes | Yes | Yes | Yes | Yes |
| Stream token | Yes | Yes | Yes | Yes | Yes | Yes |
| Stream first token | Yes | Yes | Yes | Yes | Yes | Yes |
| Stream end | Yes | Yes | Yes | Yes | Yes | Yes |
| Diagnostics | Yes | Yes | Yes | Yes | Yes | Yes |
| Metrics | Yes | Yes | Yes | Yes | Yes | Yes |

## Golden Trace Fixtures

`Fixtures/trace-golden/canonical-ai-workflow.json` is the canonical shape fixture.
It contains one trace with:

- A workflow root span.
- A child inference span with model, token, provider, and response-model attributes.
- A child tool span with tool name, type, and call ID.
- A child streaming span marked as an error with streaming metrics and an exception event.

The fixture intentionally records redaction metadata and omits raw prompt, response, tool input, and exception message content.
