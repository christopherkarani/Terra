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
    #expect(tabView.numberOfTabViewItems == 8)

    let tables = allSubviews(of: NSTableView.self, in: viewController.view)
    #expect(!tables.isEmpty)
    #expect(tables.allSatisfy { $0.numberOfRows == 0 })
  }

  @Test("SpanDetailViewController applies AppSettings span event row limit")
  func spanDetailViewControllerAppliesConfiguredEventRowLimit() throws {
    AppSettings.spanEventsRowLimit = 30
    defer { AppSettings.spanEventsRowLimit = AppSettings.defaultSpanEventsRowLimit }

    let traceId = TraceId()
    var span = makeSpan(
      name: "Root",
      traceId: traceId,
      start: Date(timeIntervalSince1970: 1),
      end: Date(timeIntervalSince1970: 2)
    )
    let events = (0..<40).map { index in
      SpanData.Event(
        name: "provider.event.\(index)",
        timestamp: Date(),
        attributes: ["idx": .int(index)]
      )
    }
    span = span.settingEvents(events)

    let viewController = SpanDetailViewController()
    viewController.loadViewIfNeeded()
    viewController.updateSpan(span)

    let tabView = try #require(allSubviews(of: NSTabView.self, in: viewController.view).first)
    let eventTables = tabView.tabViewItems
      .compactMap { $0.view as? NSScrollView }
      .compactMap { $0.documentView as? NSTableView }
      .filter { table in
        table.tableColumns.count == 3
          && table.tableColumns.first?.title == "Event"
      }
    #expect(!eventTables.isEmpty)
    #expect(eventTables.contains(where: { $0.numberOfRows == 30 }))
    #expect(eventTables.contains(where: { $0.numberOfRows == 40 }) == false)
  }

  @Test("TraceListViewController remains interactive with large trace collections")
  func traceListViewControllerLargeDatasetInteractionStaysStable() throws {
    let baseTraceID = TraceId()
    var traces: [Trace] = []
    traces.reserveCapacity(320)

    for index in 0..<320 {
      let traceID = index == 0 ? baseTraceID : TraceId()
      let span = makeSpan(
        name: "Trace \(index)",
        traceId: traceID,
        start: Date(timeIntervalSince1970: TimeInterval(index * 2)),
        end: Date(timeIntervalSince1970: TimeInterval((index * 2) + 1))
      )
      traces.append(try Trace(fileName: "trace-\(index)", spans: [span]))
    }

    let viewController = TraceListViewController()
    viewController.loadViewIfNeeded()
    viewController.updateTraces(traces)

    #expect(labelValues(in: viewController.view).contains("Traces (320)"))
    let table = try #require(allSubviews(of: NSTableView.self, in: viewController.view).first)

    var selectedID: String?
    viewController.onSelectTrace = { selectedID = $0.id }

    viewController.updateSearchQuery("trace-31")
    #expect(labelValues(in: viewController.view).contains("Traces (11)"))

    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    viewController.tableViewSelectionDidChange(
      Notification(name: NSTableView.selectionDidChangeNotification, object: table)
    )
    #expect(selectedID != nil)
  }

  @Test("SpanDetailViewController keeps recommendation and anomaly tabs bounded at high volume")
  func spanDetailViewControllerHighVolumeRecommendationAndAnomalyRowsStayBounded() throws {
    AppSettings.spanEventsRowLimit = 120
    defer { AppSettings.spanEventsRowLimit = AppSettings.defaultSpanEventsRowLimit }

    let traceId = TraceId()
    var span = makeSpan(
      name: "HighVolumeSpan",
      traceId: traceId,
      start: Date(timeIntervalSince1970: 1),
      end: Date(timeIntervalSince1970: 3)
    )

    let recommendationEvents = (0..<220).map { index in
      SpanData.Event(
        name: "terra.recommendation",
        timestamp: Date().addingTimeInterval(Double(index) * 0.001),
        attributes: [
          "terra.recommendation.kind": .string("thermal_slowdown"),
          "idx": .int(index)
        ]
      )
    }
    let anomalyEvents = (0..<220).map { index in
      SpanData.Event(
        name: "terra.anomaly.stalled_token",
        timestamp: Date().addingTimeInterval(Double(index) * 0.001),
        attributes: [
          "terra.anomaly.kind": .string("stalled_token"),
          "idx": .int(index)
        ]
      )
    }
    let lifecycleEvents = (0..<220).map { index in
      SpanData.Event(
        name: "terra.token.lifecycle",
        timestamp: Date().addingTimeInterval(Double(index) * 0.001),
        attributes: [
          "terra.token.index": .int(index + 1)
        ]
      )
    }
    span = span.settingEvents(recommendationEvents + anomalyEvents + lifecycleEvents)

    let viewController = SpanDetailViewController()
    viewController.loadViewIfNeeded()
    viewController.updateSpan(span)

    let tabView = try #require(allSubviews(of: NSTabView.self, in: viewController.view).first)

    func rows(for label: String) -> Int? {
      guard let item = tabView.tabViewItems.first(where: { $0.label == label }),
            let scroll = item.view as? NSScrollView,
            let table = scroll.documentView as? NSTableView
      else {
        return nil
      }
      return table.numberOfRows
    }

    #expect(rows(for: "Recommendations") == 120)
    #expect(rows(for: "Anomalies") == 120)
    #expect(rows(for: "Lifecycle") == 120)
  }
}
