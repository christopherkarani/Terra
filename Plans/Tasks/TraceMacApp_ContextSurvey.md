Prompt:
Survey the codebase for TerraTraceKit models/renderers, TraceStore actor API, OTLPHTTPServer configuration, and existing SwiftPM targets. Produce a concise context summary only.

Goal:
Identify available APIs and any gaps or risks before implementation.

Task Breakdown:
- Locate TerraTraceKit models and renderer types, summarize their inputs/outputs and usage patterns.
- Inspect TraceStore actor public API for snapshot/change stream support.
- Inspect OTLPHTTPServer startup/configuration and lifecycle control.
- Confirm SwiftPM package structure and existing executable targets (if any).
- Note any constraints or missing APIs that affect the plan assumptions.

Expected Output:
- A short context summary with file references and key API signatures (no code changes).
