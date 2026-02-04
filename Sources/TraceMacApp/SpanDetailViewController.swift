import AppKit
import TerraTraceKit

@MainActor
final class SpanDetailViewController: NSViewController {
  private let scrollView = NSScrollView()
  private let textView = NSTextView()
  private let emptyTitleLabel = NSTextField(labelWithString: "No trace selected")
  private let emptySubtitleLabel = NSTextField(labelWithString: "Choose a trace to inspect spans")
  private let emptyStack = NSStackView()

  override func loadView() {
    view = NSView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureLayout()
  }

  func update(snapshot: TraceSnapshot, selectedTraceID: TraceID?, selectedSpanID: SpanID?) {
    textView.string = detailText(snapshot: snapshot, selectedTraceID: selectedTraceID, selectedSpanID: selectedSpanID)
    let hasTrace = selectedTraceID != nil
    scrollView.isHidden = !hasTrace
    emptyStack.isHidden = hasTrace
  }

  private func configureLayout() {
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true

    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.font = TraceUIStyle.Typography.mono
    textView.textColor = TraceUIStyle.Colors.primaryText
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.containerSize = NSSize(
      width: scrollView.contentSize.width,
      height: .greatestFiniteMagnitude
    )

    scrollView.documentView = textView

    emptyTitleLabel.font = TraceUIStyle.Typography.emptyTitle
    emptyTitleLabel.textColor = TraceUIStyle.Colors.secondaryText
    emptyTitleLabel.alignment = .center

    emptySubtitleLabel.font = TraceUIStyle.Typography.emptySubtitle
    emptySubtitleLabel.textColor = TraceUIStyle.Colors.tertiaryText
    emptySubtitleLabel.alignment = .center

    emptyStack.orientation = .vertical
    emptyStack.spacing = TraceUIStyle.Spacing.xSmall
    emptyStack.alignment = .centerX
    emptyStack.translatesAutoresizingMaskIntoConstraints = false
    emptyStack.addArrangedSubview(emptyTitleLabel)
    emptyStack.addArrangedSubview(emptySubtitleLabel)

    view.addSubview(scrollView)
    view.addSubview(emptyStack)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    NSLayoutConstraint.activate([
      emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      emptyStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: TraceUIStyle.Spacing.large),
      emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -TraceUIStyle.Spacing.large)
    ])

    scrollView.isHidden = true
  }

  private func detailText(
    snapshot: TraceSnapshot,
    selectedTraceID: TraceID?,
    selectedSpanID: SpanID?
  ) -> String {
    guard let selectedTraceID else {
      return "Select a trace to inspect spans."
    }

    guard let spans = snapshot.traces[selectedTraceID] else {
      return "Trace \(selectedTraceID.short) is no longer available."
    }

    if let selectedSpanID,
       let span = spans.first(where: { $0.spanID == selectedSpanID }) {
      return render(span: span)
    }

    return "Trace \(selectedTraceID.short) selected.\nSelect a span to view details."
  }

  private func render(span: SpanRecord) -> String {
    var lines: [String] = []
    lines.append("Span: \(span.name)")
    lines.append("Span ID: \(span.spanID.hex)")
    lines.append("Trace ID: \(span.traceID.hex)")
    lines.append("Duration: \(span.durationNanoseconds) ns")
    lines.append("Status: \(span.status.rawValue)")

    if !span.attributes.items.isEmpty {
      lines.append("")
      lines.append("Attributes:")
      for attribute in span.attributes.items {
        lines.append("- \(attribute.key): \(attribute.value)")
      }
    } else {
      lines.append("")
      lines.append("Attributes: (none)")
    }

    return lines.joined(separator: "\n")
  }
}
