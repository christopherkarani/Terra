Prompt:
Add XCTest coverage for OTLP decoding, ingestion, rendering, and end-to-end receiver flow per the plan.

Goal:
Provide deterministic, behavior-focused tests that lock in decoding correctness, tree construction, rendering stability, and receiver integration without relying on real time.

Task Breakdown:
1. Create OTLP protobuf fixtures with fixed timestamps and IDs; avoid real time in tests.
2. Add decoding tests for identity, gzip, and deflate payloads, including decompressed-size limit rejection.
3. Add ingestion tests validating parent/child tree correctness, and missing-parent behavior that re-parents when the parent arrives later.
4. Add rendering tests for deterministic stream line output and stable tree output ordering.
5. Add end-to-end test that starts the receiver on an ephemeral port, POSTS a valid OTLP request, and asserts spans are ingested and rendered.
6. Keep tests in XCTest, matching current repo conventions, and avoid introducing Swift Testing unless required.

Expected Output:
- New XCTest cases covering decode, ingestion, rendering, and e2e pathways.
- Stable fixtures and assertions with deterministic ordering.
- No implementation beyond tests; no plan edits.
