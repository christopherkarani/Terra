Prompt:
Build the AppKit UI and wire it to TraceViewModel per the plan: split view with trace list, timeline, and detail panels.

Goal:
Deliver a polished macOS AppKit trace viewer with three labeled feature areas and correct data flow from persistence to UI.

Task Breakdown:
1. Implement AppKit window and split view layout with areas A (list/filter), B (timeline), C (detail).
2. Build trace list UI with search/filter controls and selection handling wired to list view model.
3. Build timeline view rendering of spans with highlights for errors/critical spans and long durations.
4. Build detail panel UI for selected span attributes, events, and links.
5. Wire view models to UI using simple callbacks/notifications; no SwiftUI.
6. Validate manual behavior against Integration/QA checklist.

Expected Output:
- New or updated AppKit UI source files under `Sources/` and project wiring.
- App launches and displays data from persistence with correct selection and updates.
