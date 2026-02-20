import AppKit
import Foundation
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import TerraTraceKit
import Testing
@testable import TraceMacAppUI

private func makeSpan(
  name: String,
  traceId: TraceId,
  spanId: SpanId = SpanId(),
  parentSpanId: SpanId? = nil,
  start: Date,
  end: Date,
  status: Status = .unset
) -> SpanData {
  var span = SpanData(
    traceId: traceId,
    spanId: spanId,
    traceFlags: TraceFlags(),
    traceState: TraceState(),
    resource: Resource(),
    instrumentationScope: InstrumentationScopeInfo(),
    name: name,
    kind: .internal,
    startTime: start,
    endTime: end,
    hasRemoteParent: false,
    hasEnded: true
  )
  if let parentSpanId {
    span = span.settingParentSpanId(parentSpanId)
  }
  return span.settingStatus(status)
}

private func allSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
  var matches: [T] = []
  for subview in root.subviews {
    if let typed = subview as? T {
      matches.append(typed)
    }
    matches.append(contentsOf: allSubviews(of: type, in: subview))
  }
  return matches
}

private func labelValues(in root: NSView) -> [String] {
  allSubviews(of: NSTextField.self, in: root).map(\.stringValue)
}

@MainActor
@Suite("Trace AppKit View Controllers", .serialized)
struct TraceAppKitViewControllerTests {
  init() {
    _ = NSApplication.shared
  }

  @Test("TraceListViewController updates header count and supports programmatic selection")
  func traceListViewControllerHeaderAndSelection() throws {
    let traceIdA = TraceId()
    let traceIdB = TraceId()
    let traceA = try Trace(
      fileName: "1000",
      spans: [
        makeSpan(
          name: "Home",
          traceId: traceIdA,
          start: Date(timeIntervalSince1970: 10),
          end: Date(timeIntervalSince1970: 12)
        )
      ]
    )
    let traceB = try Trace(
      fileName: "2000",
      spans: [
        makeSpan(
          name: "Checkout",
          traceId: traceIdB,
          start: Date(timeIntervalSince1970: 20),
          end: Date(timeIntervalSince1970: 24)
        )
      ]
    )

    let viewController = TraceListViewController()
    viewController.loadViewIfNeeded()
    viewController.updateTraces([traceA, traceB])

    #expect(labelValues(in: viewController.view).contains("Traces (2)"))
    let table = try #require(allSubviews(of: NSTableView.self, in: viewController.view).first)

    var selectedID: String?
    viewController.onSelectTrace = { selectedID = $0.id }

    viewController.selectTrace(traceA)
    #expect(table.selectedRow == 1)
    #expect(selectedID == nil)

    viewController.updateSearchQuery("check")
    #expect(labelValues(in: viewController.view).contains("Traces (1)"))

    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    viewController.tableViewSelectionDidChange(
      Notification(name: NSTableView.selectionDidChangeNotification, object: table)
    )
    #expect(selectedID == "2000")
  }

  @Test("SpanListViewController loads an empty shell before data")
  func spanListViewControllerLoadsShell() throws {
    let viewController = SpanListViewController()
    viewController.loadViewIfNeeded()
    viewController.clear()

    #expect(labelValues(in: viewController.view).contains("Spans (0)"))
    let table = try #require(allSubviews(of: NSTableView.self, in: viewController.view).first)
    #expect(table.numberOfRows == 0)
  }

  @Test("SpanDetailViewController starts with empty detail tables")
  func spanDetailViewControllerStartsEmpty() throws {
    let viewController = SpanDetailViewController()
    viewController.loadViewIfNeeded()
    viewController.clear()

    let tabView = try #require(allSubviews(of: NSTabView.self, in: viewController.view).first)
    #expect(tabView.numberOfTabViewItems == 6)

    let tables = allSubviews(of: NSTableView.self, in: viewController.view)
    #expect(!tables.isEmpty)
    #expect(tables.allSatisfy { $0.numberOfRows == 0 })
  }
}
