import AppKit
import OpenTelemetrySdk
import TerraTraceKit

final class TraceTimelineViewController: NSViewController {
  var onSelectSpan: ((SpanData) -> Void)?

  private let headerLabel = NSTextField(labelWithString: "Timeline")
  private let timelineView = TraceTimelineView()
  private let scrollView = NSScrollView()

  override func loadView() {
    view = NSView()

    TraceUI.styleSectionHeader(headerLabel)

    scrollView.documentView = timelineView
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    TraceUI.styleSurface(scrollView)

    let stack = NSStackView(views: [headerLabel, scrollView])
    stack.orientation = .vertical
    stack.spacing = TraceUI.sectionSpacing
    stack.edgeInsets = TraceUI.contentInsets
    stack.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    timelineView.onSelectSpan = { [weak self] span in
      self?.onSelectSpan?(span)
    }
  }

  func updateTrace(_ trace: Trace) {
    timelineView.update(with: TimelineViewModel(trace: trace))
  }

  func clearTrace() {
    timelineView.clear()
  }

  func selectSpan(_ span: SpanData) {
    timelineView.selectSpan(span)
  }
}
