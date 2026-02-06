Prompt:
Implement TracePersistence per plan and T2 tests: locate the traces folder, list files, read contents, and decode SpanData arrays using the wrapper decode strategy.

Goal:
Provide a small, correct persistence layer that discovers and decodes trace files from disk with clear errors and no extra dependencies.

Task Breakdown:
1. Implement a TracePersistence module (or folder) with locator, reader, and decoder types.
2. Resolve the Terra traces folder path and list files sorted by file name timestamp.
3. Read file contents as Data and surface missing/invalid file errors.
4. Decode by wrapping data with "[" and "null]" before JSON decoding into [SpanData?], then compact to [SpanData].
5. Keep APIs minimal and Swifty with internal visibility by default.
6. Make all T2 tests pass without changing test expectations.

Expected Output:
- New or updated source files under `Sources/` implementing TracePersistence.
- All T2 tests pass.
