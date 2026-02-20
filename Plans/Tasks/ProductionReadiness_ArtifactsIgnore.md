# Task: Trace CLI — Artifacts + Ignore

Prompt:
Remove tracked build artifacts and update `.gitignore` so generated Trace CLI outputs are not committed again.

Goal:
Keep the repo source-only by deleting build outputs and enforcing ignore rules.

Task Breakdown:
- Identify tracked build artifacts (e.g., `.d`, `.o`, `.swiftdeps`, `.dia`) related to Trace CLI builds.
- Remove those artifacts from version control.
- Update `.gitignore` with minimal rules to exclude these artifacts and SwiftPM build outputs.
- Verify that no source files are removed.

Expected Output:
- Tracked build artifacts deleted.
- `.gitignore` updated with targeted ignore rules.
- Brief summary of removed artifact categories.
