# Lessons

## 2026-03-26

- Verify the target repository path before planning or mutating files; this workspace uses `/Users/chriskarani/CodingProjects/Terra`, not any checkout under `Downloads`.
- When adding a new canonical tracing entry point, preserve the existing semantic attributes and roll-up metrics so dashboards and saved queries do not regress during migration.
- Prefer the source signatures over older audit notes when the two disagree.
- Terra's canonical call surface now uses raw `String` model and tool-call identifiers, with typed wrappers retained only for compatibility.
- `TraceHandle` is the public place for per-call annotations; `Operation` itself only exposes `capture(_:)` and `run(_:)`.
- When docs mention both canonical and compatibility APIs, label the compatibility path explicitly so agents do not treat it as the preferred API.
- If a documentation example must keep a compatibility wrapper for compileability, make the wrapper type explicit in the variable declaration rather than mixing wrapper-only APIs with plain `String` bindings.
- When bridging a compatibility handle onto a Terra-owned span, do not bypass operation-scoped callbacks for behavior that carries privacy or policy decisions. `TraceHandle.recordError` must keep using the injected callback so composable operations preserve `captureMessage` gating.
- For skill creation work, keep one canonical reference file per concept; duplicate topic files make the skill harder for agents to follow and add noise without adding coverage.
- TerraViewer guidance needs an explicit emission matrix, not just a narrative contract, when the app consumes SDK telemetry across multiple surfaces.
- TerraViewer identity guidance should split resource attributes from span attributes, and content guidance should explicitly prefer raw content vs hash vs length based on privacy.
- TerraViewer readability depends on naming conventions too; the skill should spell out how to name sessions, workflow roots, agents, tools, and model routes instead of assuming the caller will choose good defaults.
