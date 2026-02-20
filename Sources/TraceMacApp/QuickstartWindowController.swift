import AppKit

final class QuickstartWindowController: NSWindowController {
  private let viewController: QuickstartViewController

  init() {
    viewController = QuickstartViewController()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Instrument Your App (60s)"
    window.isReleasedWhenClosed = false
    window.contentViewController = viewController
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class QuickstartViewController: NSViewController {
  private let textView = NSTextView()
  private let scrollView = NSScrollView()
  private let copyButton = NSButton(title: "Copy", target: nil, action: nil)

  override func loadView() {
    view = NSView()

    let titleLabel = NSTextField(labelWithString: "Instrument your app to generate traces:")
    titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

    textView.isEditable = false
    textView.isSelectable = true
    textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    textView.string = Self.quickstartText
    textView.drawsBackground = false

    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    TraceUI.styleSurface(scrollView)

    copyButton.bezelStyle = .rounded
    copyButton.target = self
    copyButton.action = #selector(copyToClipboard)

    let buttonRow = NSStackView(views: [copyButton])
    buttonRow.orientation = .horizontal
    buttonRow.alignment = .centerY

    let stack = NSStackView(views: [titleLabel, scrollView, buttonRow])
    stack.orientation = .vertical
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    stack.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
    ])
  }

  @objc private func copyToClipboard() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(textView.string, forType: .string)
  }

  private static let quickstartText = """
  import Terra

  // 1) Install OpenTelemetry wiring once (OTLP export optional, persistence recommended).
  try Terra.installOpenTelemetry(
    .init(
      enableLogs: false,
      persistence: .init(storageURL: Terra.defaultPersistenceStorageURL())
    )
  )

  // 2) Install Terra privacy defaults (safe by default).
  Terra.install(.init(privacy: .default))

  // 3) Instrument the boundaries you own.
  let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", promptCapture: .never)
  try await Terra.withInferenceSpan(request) { scope in
    scope.addEvent("inference.start")
    // ... run your model
    scope.addEvent("inference.end")
  }
  """
}

