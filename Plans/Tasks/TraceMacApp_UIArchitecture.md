Prompt:
Implement the AppKit UI architecture: window layout with trace list, timeline view, and span detail inspector. Use NSSplitViewController and dedicated view controllers/views.

Goal:
Deliver the core UI skeleton wired to the view model, ready for renderer integration.

Task Breakdown:
- Create window scene and root NSSplitViewController layout (left list, center timeline, right inspector).
- Implement TraceListViewController with NSTableView data source/delegate bound to view model.
- Implement SpanDetailViewController (table/outline for attributes).
- Provide an empty/loading state UI and basic toolbar with filter/search placeholders.
- Wire selection changes to update timeline and detail views.

Expected Output:
- AppKit view controllers and views under Sources/TraceMacApp/.
- Split view layout visible on launch and responds to selection changes.
