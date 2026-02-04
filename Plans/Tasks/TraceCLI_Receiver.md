Prompt:
Implement the minimal OTLP HTTP receiver for the terra CLI using Network.framework, handling POST /v1/traces with Content-Length and returning OTLP HTTP responses.

Goal:
Provide a safe, deterministic HTTP/1.1 receiver that accepts OTLP trace exports, enforces size limits, routes requests, and closes connections after each response as specified in the plan.

Task Breakdown:
1. Implement a minimal HTTP/1.1 server using NWListener and NWConnection in the terra executable target.
2. Parse request line and headers, requiring POST, path /v1/traces, and Content-Length. Reject unsupported method/path with 4xx.
3. Enforce body size caps and reject missing Content-Length with 411 Length Required.
4. Explicitly handle unsupported Transfer-Encoding: chunked with 411 Length Required, and Expect: 100-continue with 417 Expectation Failed.
5. Read full request body, pass headers and body to TerraTraceKit decode API, and on success ingest into the in-memory store.
6. Return 200 OK with an OTLP ExportTraceServiceResponse protobuf body, allowing empty body if the proto is not easily built.
7. Return 4xx or 5xx with text/plain error summary for decode or internal failures, and always close the connection.

Expected Output:
- A NWListener-based receiver that binds to the requested host/port and handles one request per connection.
- Robust request parsing and size limits that follow plan constraints.
- Integration point that calls TerraTraceKit decoding and store ingestion.
- Clear error mapping to HTTP responses and no plan edits.
