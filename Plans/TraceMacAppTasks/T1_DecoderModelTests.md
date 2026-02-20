Prompt:
Create Swift Testing tests that define the decoder contract and core model contracts for the TraceMacApp plan. Tests must fail on current main and not include implementation code.

Goal:
Specify expected decoding behavior for comma-separated JSON arrays of SpanData and expected model invariants/metadata so implementation can be safely built to those tests.

Task Breakdown:
1. Add Swift Testing target scaffolding if missing and create a new test file for decoder/model contracts.
2. Write tests for decoder behavior: wrapping input with "[" and "null]" before decoding, handling empty/whitespace-only files, and ensuring invalid JSON produces a decoding error.
3. Write tests for model assembly expectations: Trace has stable identifier derived from file name (milliseconds since reference date), start/end boundaries computed from spans, duration computed, and error/critical span flags computed.
4. Write tests for timeline ordering and span grouping rules used by the model layer (e.g., spans sorted by start time, parent/child relationships if present in SpanData).
5. Keep tests deterministic with small inlined JSON fixtures; no filesystem I/O in this task.

Expected Output:
- New Swift Testing test file(s) under `Tests/` covering decoder and model contracts.
- Tests fail because implementation does not yet exist.
