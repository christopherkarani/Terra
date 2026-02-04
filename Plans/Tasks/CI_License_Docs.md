Prompt:
Add Apache-2.0 licensing, CI gate for tests, and update documentation for production readiness changes.

Goal:
Provide legal clarity, enforce automated verification, and align docs with actual behavior and new APIs.

Task Breakdown:
- Add `LICENSE` file (Apache-2.0) and ensure README references it.
- Add CI configuration to run Swift Testing and `swift test` on PRs.
- Update README/docs to cover:
- Installation and production usage.
- Instrumentation versioning and how to access `instrumentationVersion`.
- Persistence path expectations per platform.
- CI status badge if applicable.
- Keep docs accurate to current runtime behavior post-fixes.

Expected Output:
- `LICENSE` file.
- CI configuration for tests.
- Updated README/docs reflecting licensing, CI, instrumentation versioning, and persistence paths.
