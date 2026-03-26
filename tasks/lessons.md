# Lessons

## 2026-03-26

- Verify the target repository path before planning or mutating files; this workspace uses `/Users/chriskarani/CodingProjects/Terra`, not any checkout under `Downloads`.
- When adding a new canonical tracing entry point, preserve the existing semantic attributes and roll-up metrics so dashboards and saved queries do not regress during migration.
- Prefer the source signatures over older audit notes when the two disagree.
- Terra's canonical call surface now uses raw `String` model and tool-call identifiers, with typed wrappers retained only for compatibility.
- `TraceHandle` is the public place for per-call annotations; `Operation` itself only exposes `capture(_:)` and `run(_:)`.
- When docs mention both canonical and compatibility APIs, label the compatibility path explicitly so agents do not treat it as the preferred API.
- If a documentation example must keep a compatibility wrapper for compileability, make the wrapper type explicit in the variable declaration rather than mixing wrapper-only APIs with plain `String` bindings.
