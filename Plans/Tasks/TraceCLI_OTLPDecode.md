Prompt:
Implement the OTLP HTTP decoding pipeline in TerraTraceKit: decode request bytes, decompress gzip/deflate/identity with size limits, parse OTLP protobuf, and map to internal span/resource models.

Goal:
Provide a deterministic, safe, and typed decoding layer that converts OTLP ExportTraceServiceRequest payloads into SpanRecord models ready for ingestion, without touching the plan or other components.

Task Breakdown:
1. Define or confirm internal model types needed for decoding output: TraceID, SpanID, SpanRecord, Resource, Attributes, and any supporting enums for status/span kind.
2. Implement a decoding pipeline API in TerraTraceKit that accepts raw HTTP body bytes and headers and returns a collection of SpanRecord with resource/attributes.
3. Implement decompression for Content-Encoding: gzip, deflate, identity using Compression streams, and enforce maximum compressed and maximum decompressed byte limits.
4. Parse OTLP protobuf bytes into Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest using OpenTelemetryProtocolExporterCommon types.
5. Map OTLP spans to SpanRecord, extracting IDs, timestamps, duration, name, and key attributes, always including service.name, span.kind, status.code, gen_ai.*, and terra.* if present.
6. Define error types with clear cases for unsupported encoding, size limit exceeded, invalid protobuf, and missing or malformed data.
7. Ensure deterministic attribute ordering in any stored representation used later by renderers.

Expected Output:
- New decoding module in TerraTraceKit with a clear public API (internal visibility by default) and typed errors.
- Decompression utilities for gzip/deflate/identity with size caps and testability.
- OTLP-to-SpanRecord mapping logic that preserves required attributes and IDs.
- No changes to CLI or receiver; no plan edits.
