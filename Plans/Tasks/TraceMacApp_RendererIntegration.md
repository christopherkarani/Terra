Prompt:
Integrate existing TerraTraceKit renderer APIs into the AppKit timeline view. Map selected trace data to renderer input and ensure main-thread drawing with minimal allocations.

Goal:
Render a trace timeline using existing renderers inside an NSView-backed custom view.

Task Breakdown:
- Identify renderer entry points and required inputs.
- Implement TraceTimelineView (NSView) that uses renderer to draw.
- Map view model selection to renderer input without copying large data.
- Ensure drawing happens on main thread and is performant.
- Add any adapter types needed to bridge renderer expectations.

Expected Output:
- TraceTimelineView implementation wired to the renderer.
- Timeline updates correctly when selection changes.
