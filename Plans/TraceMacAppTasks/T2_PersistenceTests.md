Prompt:
Create Swift Testing tests for the TracePersistence layer: locating trace files, reading contents, and decoding SpanData arrays from disk per the plan.

Goal:
Lock down persistence behaviors and error handling for file discovery, reading, and decoding against the Terra traces folder format.

Task Breakdown:
1. Add a new Swift Testing file for persistence tests.
2. Write tests for trace folder discovery and file listing, using a temporary directory with file names as milliseconds since reference date.
3. Write tests that reading a file returns raw contents unchanged and handles missing files with a clear error.
4. Write tests that decoding uses the wrapper "[" + data + "null]" and successfully produces expected SpanData count.
5. Write tests for invalid file names and ensure they are ignored or surfaced per expected behavior.
6. Ensure tests are hermetic and only use temp directories created during the test run.

Expected Output:
- New Swift Testing test file(s) under `Tests/` for persistence locator/reader/decoder.
- Tests fail because persistence implementation does not yet exist.
