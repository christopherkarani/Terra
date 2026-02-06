Prompt:
Implement TraceModel per plan and T1 tests: aggregate decoded spans into trace-level metadata and structures used by view models.

Goal:
Provide a type-safe model layer that computes trace metadata (start/end/duration, error/critical flags) and stable identifiers.

Task Breakdown:
1. Define Trace and related model types as value types with minimal visibility.
2. Compute trace identifier from file name (milliseconds since reference date) and expose a stable display date.
3. Compute start, end, and duration from span timestamps with clear handling for missing data.
4. Compute derived metadata: error presence, critical/long duration spans, and parent/child relationships if present in SpanData.
5. Ensure model ordering rules used by view models are deterministic.
6. Make all T1 model tests pass without changing test expectations.

Expected Output:
- New or updated source files under `Sources/` implementing TraceModel.
- All T1 model-related tests pass.
