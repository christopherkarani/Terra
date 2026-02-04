import AppKit
import TerraTraceKit

@MainActor
final class TraceTimelineViewController: NSViewController {
  private let titleLabel = NSTextField(labelWithString: "Timeline")
  private let detailLabel = NSTextField(labelWithString: "Select a trace to view timeline")
  private let emptyTitleLabel = NSTextField(labelWithString: "No trace selected")
  private let emptySubtitleLabel = NSTextField(labelWithString: "Choose a trace to view its timeline")
  private let emptyStack = NSStackView()
  private let timelineView = TraceTimelineView()

  override func loadView() {
    view = NSView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureLayout()
  }

  func update(selectedTraceID: TraceID?, spans: [SpanRecord]?) {
    let spanCount = spans?.count ?? 0
    if let selectedTraceID {
      detailLabel.stringValue = "Trace \(selectedTraceID.short) - \(spanCount) spans"
    } else {
      detailLabel.stringValue = "Select a trace to view timeline"
    }

    if let spans, !spans.isEmpty {
      timelineView.update(model: TraceTimelineModel(spans: spans))
      emptyStack.isHidden = true
    } else {
      timelineView.update(model: nil)
      if selectedTraceID == nil {
        emptyTitleLabel.stringValue = "No trace selected"
        emptySubtitleLabel.stringValue = "Choose a trace to view its timeline"
      } else {
        emptyTitleLabel.stringValue = "No spans to display"
        emptySubtitleLabel.stringValue = "This trace has no spans yet"
      }
      emptyStack.isHidden = false
    }
  }

  private func configureLayout() {
    titleLabel.font = TraceUIStyle.Typography.title
    titleLabel.textColor = TraceUIStyle.Colors.primaryText
    detailLabel.font = TraceUIStyle.Typography.subtitle
    detailLabel.textColor = TraceUIStyle.Colors.secondaryText

    let headerStack = NSStackView(views: [titleLabel, detailLabel])
    headerStack.orientation = .vertical
    headerStack.spacing = TraceUIStyle.Spacing.xSmall
    headerStack.translatesAutoresizingMaskIntoConstraints = false

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
    emptyStack.isHidden = true

    timelineView.translatesAutoresizingMaskIntoConstraints = false
    timelineView.setContentHuggingPriority(.defaultLow, for: .vertical)
    timelineView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    view.addSubview(headerStack)
    view.addSubview(timelineView)
    view.addSubview(emptyStack)

    NSLayoutConstraint.activate([
      headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TraceUIStyle.Spacing.large),
      headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TraceUIStyle.Spacing.large),
      headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: TraceUIStyle.Spacing.large),

      timelineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      timelineView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      timelineView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: TraceUIStyle.Spacing.medium),
      timelineView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    NSLayoutConstraint.activate([
      emptyStack.centerXAnchor.constraint(equalTo: timelineView.centerXAnchor),
      emptyStack.centerYAnchor.constraint(equalTo: timelineView.centerYAnchor),
      emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: TraceUIStyle.Spacing.large),
      emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -TraceUIStyle.Spacing.large)
    ])
  }
}
