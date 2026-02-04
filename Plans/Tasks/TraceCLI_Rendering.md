Prompt:
Implement TerraTraceKit renderers for stream lines and tree views, plus filtering and deterministic ordering.

Goal:
Provide stable, demo-grade CLI output formats for live streaming and per-trace trees, matching the plan’s required line formats and ordering guarantees.

Task Breakdown:
1. Define renderer interfaces or types in TerraTraceKit for stream and tree outputs, taking snapshot data from the store to avoid concurrency issues.
2. Implement stream line rendering with format: timestamp duration name traceShort spanShort key=val..., with deterministic attribute ordering.
3. Implement tree rendering: group by traceId, build parent/child adjacency, sort children by start time, and handle missing parents as roots.
4. Ensure tree rendering re-parents correctly when a parent arrives after children by building from full snapshot at render time.
5. Implement filtering options: name prefix filter and traceId filter, applied consistently to stream and tree output.
6. Ensure output ordering is stable and deterministic across runs with identical inputs.

Expected Output:
- Stream renderer with stable line format and deterministic attribute ordering.
- Tree renderer with correct parent/child ordering and re-parenting at render time.
- Filter support for name prefix and traceId.
- No changes to receiver or CLI; no plan edits.
