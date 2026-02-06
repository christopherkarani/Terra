Prompt:
Produce an integration and manual QA checklist for the TraceMacApp, covering data flow from persistence to UI and correctness of key behaviors.

Goal:
Provide a concise, actionable checklist to validate the end-to-end trace viewer without UI automation tests.

Task Breakdown:
1. Verify traces folder discovery and file listing order by timestamp.
2. Verify decoding of comma-separated SpanData arrays using wrapper decode strategy.
3. Verify trace list sorting, searching, and selection behavior.
4. Verify timeline ordering, lane mapping, and highlighting of errors/critical/long spans.
5. Verify detail panel updates for selected span and reset on deselection.
6. Validate error states for missing or invalid files.

Expected Output:
- A checklist sectioned by layer (persistence, model, view model, UI) in this file.

---

# Integration / Manual QA Checklist (TraceMacApp)

## Pre-flight
- Ensure you have at least one valid trace file:
  - Run `swift run TerraSample` from the repo root to generate local traces, or use “Load Sample Traces” in-app.
- Confirm where traces are located:
  - Default: `~/Library/Caches/opentelemetry/terra/traces`
  - App override: “Choose Traces Folder…” (File menu)

## Persistence (file discovery + decode)
- Traces folder exists and is readable:
  - “Open Traces Folder in Finder” works and shows numeric-named files.
- File discovery behavior:
  - Only numeric filenames are considered “trace files”.
  - List order is newest → oldest by timestamp parsed from filename (milliseconds since reference date).
- Decode behavior:
  - Comma-separated `SpanData` arrays decode correctly (wrapper strategy: `[` + data + `null]`).
  - Empty/whitespace files decode to empty spans (no crash).
  - Corrupt files are skipped with a user-visible “some files failed” posture (no app crash).

## Model (trace assembly)
- Each trace produces stable identifiers:
  - Trace ID shown in list matches a stable value derived from file/spans.
- Boundary correctness:
  - Trace duration equals min(start) → max(end) over spans.
  - Parent/child relationships appear correctly when span parent IDs are present.

## View models (selection + filtering)
- Trace list:
  - Default sort is newest first.
  - Search filters by trace id or span name.
  - Selection is preserved when filtering (selected trace remains selected if still present).
- Timeline:
  - Spans are ordered by start time.
  - Overlapping spans occupy separate lanes (no visual overlap).
  - “Important” highlighting triggers for:
    - error status
    - long durations (relative threshold)
- Detail panel:
  - Selecting a span updates attributes/events/links tabs.
  - Clearing selection resets the detail tables (no stale content).

## AppKit UI (manual interaction)
- On first launch (fresh prefs):
  - Onboarding window appears and all buttons do something sensible:
    - Open/Choose traces folder
    - Load sample traces
    - Toggle watch folder
    - Instrument Your App (60s) opens quickstart window
    - Done dismisses onboarding
- Main window layout:
  - Left: trace list + search
  - Middle: timeline/graph
  - Right: span details
- Reload:
  - “Reload Traces” refreshes the list and the currently selected trace updates if changed.
- Watch folder:
  - Toggle “Watch Traces Folder”
  - Generate new traces (e.g., re-run `TerraSample`) and confirm the UI reloads automatically.

## Licensing + trial gates (paid-user readiness)
- Trial state:
  - Title shows “Trial (Xd left)” during trial window.
  - After trial ends, “Watch Traces Folder” is gated (activation required alert).
- Activation:
  - “Activate License…” accepts a valid key and flips status to Licensed.
  - “Deactivate License” removes the key and returns to Trial/Expired state.

## Updates + privacy toggles (production gate)
- Sparkle plumbing:
  - If Sparkle is not included, “Check for Updates…” should present “not available in this build” (or be disabled).
  - If Sparkle is included and configured, “Check for Updates…” invokes an update check.
- Privacy posture:
  - Privacy Policy / EULA menu items open configured URLs; if unconfigured, they should explain what’s missing.
  - Telemetry posture is opt-in (crash reporting toggle is off by default unless you explicitly enable it).

## Diagnostics + supportability
- Export diagnostics:
  - “Export Diagnostics…” produces a zip containing:
    - `diagnostics.json` (settings + license summary)
    - `trace_files.json` (trace file inventory)
    - app log file (if present)
- Crash report access:
  - “Reveal Crash Reports in Finder” opens `~/Library/Logs/DiagnosticReports`.
