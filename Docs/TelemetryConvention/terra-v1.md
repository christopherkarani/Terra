# Terra v1 Open Telemetry Convention

## 1. Scope

`terra.v1` is the single on-device inference telemetry contract for all Terra runtimes.
It defines required trace-level attributes, stage-aware span naming, streaming lifecycle
events, hardware telemetry, recommendation/anomaly signals, and privacy/compliance metadata.

The contract is versioned by `terra.semantic.version` and validated at ingestion.
In a breaking change window, unknown major versions are rejected.

## 2. Required Contract Attributes

The following resource attributes are required for all Terra spans:

- `terra.semantic.version` (string, e.g. `v1`)
- `terra.schema.family` (string, must be `terra`)
- `terra.runtime`
- `terra.request.id`
- `terra.session.id`
- `terra.model.fingerprint`

The runtime must be one of:

- `coreml`
- `foundation_models`
- `mlx`
- `ollama`
- `lm_studio`
- `llama_cpp`
- `openclaw_gateway`
- `http_api`

## 3. Canonical Span Names

Terra emits spans with these names:

- `terra.model.load`
- `terra.inference`
- `terra.stage.prompt_eval`
- `terra.stage.decode`
- `terra.stream.lifecycle`

The telemetry pipeline may emit additional events for compatibility, but these names are the
interop baseline.

## 4. Streaming Timing Semantics

Timing is measured from monotonic clocks in every runtime path. Non-decreasing duration
constraints:

- `terra.latency.ttft_ms` (time to first token)
- `terra.latency.e2e_ms` (end-to-end span duration)
- `terra.latency.prompt_eval_ms`
- `terra.latency.decode_ms`
- `terra.latency.tail_p95_ms`
- `terra.latency.tail_p99_ms`
- `terra.stream.time_to_first_token_ms`
- `terra.stream.tokens_per_second`
- `terra.stream.output_tokens`
- `terra.stream.chunk_count`

Per-token lifecycle events are recorded for streaming paths:

- `terra.stream.lifecycle`
- `terra.stage.prompt_eval`
- `terra.stage.decode`
- optional token anomaly events: `terra.anomaly.stalled_token`

## 5. Stage Attribution

Stages are explicit attributes on events/spans:

- `terra.stage.name`: `model_load` | `prompt_eval` | `decode` | `finish`
- `terra.stage.token_count`: number of tokens for a finished stage
- `terra.token.index`: token sequence number inside stream path
- `terra.token.gap_ms`: delta from previous token chunk
- `terra.token.stage`: stage associated with the token event

## 6. Hardware Telemetry

Runtime telemetry may emit one or more events per span with:

- `terra.process.thermal_state`
- `terra.hw.power_state`
- `terra.hw.memory_pressure`
- `terra.process.memory_resident_delta_mb`
- `terra.process.memory_peak_mb` / `terra.hw.rss_mb`
- `terra.hw.memory_churn_mb`
- `terra.hw.gpu_occupancy_pct`
- `terra.hw.ane_utilization_pct`

## 7. Quality + Drift Signals

- Recommendations: `terra.recommendation` event with `terra.recommendation.kind` and optional metadata
- Anomalies: `terra.anomaly.*` family with optional score and baseline identifiers
- Tail latency baselines and confidence metadata may be attached to anomaly/recommendation events

## 8. Compliance and Control

Privacy/compliance controls are first-class attributes:

- `terra.privacy.content_policy`
- `terra.privacy.content_redaction`
- `terra.anonymization.key_id`
- `terra.policy.blocked` / `terra.policy.reason`
- `terra.control_loop.mode`

Defaults are privacy-preserving and may be tightened with explicit opt-in controls.

## 9. Data Quality Guardrails

- Missing required attributes: reject ingestion and emit a local diagnostic event
- Unsupported `terra.semantic.version`: reject as a contract mismatch
- Per-key cardinality budgets and aggregation are applied by runtime defaults
- Unknown stage/metric values should remain absent (do not send zeros)

## 10. Stream Runtime Coverage

The same contract applies to:

- CoreML
- Foundation Models
- MLX
- Ollama
- LM Studio
- `llama_cpp`
- OpenClaw gateway
- `http_api`

Each runtime must provide stream attribution where tokenized delivery is available.
