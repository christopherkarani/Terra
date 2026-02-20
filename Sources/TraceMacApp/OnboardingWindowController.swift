import AppKit

final class OnboardingWindowController: NSWindowController {
  private let viewController: OnboardingViewController

  init(actions: OnboardingActions) {
    viewController = OnboardingViewController(actions: actions)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Welcome to TraceMacApp"
    window.isReleasedWhenClosed = false
    window.center()
    window.contentViewController = viewController
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

struct OnboardingActions {
  var openTracesFolder: @MainActor () -> Void
  var chooseTracesFolder: @MainActor () -> Void
  var loadSampleTraces: @MainActor () -> Void
  var toggleWatchFolder: @MainActor () -> Void
  var showQuickstart: @MainActor () -> Void
  var complete: @MainActor () -> Void
}

private final class OnboardingViewController: NSViewController {
  private let actions: OnboardingActions

  init(actions: OnboardingActions) {
    self.actions = actions
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView()

    let titleLabel = NSTextField(labelWithString: "Get set up in under a minute.")
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)

    let subtitleLabel = NSTextField(labelWithString: "TraceMacApp reads traces from Terra’s persistence folder (local-only by default).")
    TraceUI.styleSubtitle(subtitleLabel)

    let openFolderButton = makeButton("Open Traces Folder", action: #selector(openTracesFolder))
    let chooseFolderButton = makeButton("Choose Traces Folder…", action: #selector(chooseTracesFolder))
    let sampleButton = makeButton("Load Sample Traces", action: #selector(loadSampleTraces))
    let watchButton = makeButton("Toggle Watch Folder", action: #selector(toggleWatchFolder))
    let quickstartButton = makeButton("Instrument Your App (60s)…", action: #selector(showQuickstart))

    let doneButton = NSButton(title: "Done", target: self, action: #selector(finishOnboarding))
    doneButton.bezelStyle = .rounded
    doneButton.keyEquivalent = "\r"

    let actionsStack = NSStackView(views: [
      openFolderButton,
      chooseFolderButton,
      sampleButton,
      watchButton,
      quickstartButton
    ])
    actionsStack.orientation = .vertical
    actionsStack.spacing = 8
    actionsStack.alignment = .leading

    let stack = NSStackView(views: [titleLabel, subtitleLabel, actionsStack, doneButton])
    stack.orientation = .vertical
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    stack.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: view.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
    ])
  }

  private func makeButton(_ title: String, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.bezelStyle = .rounded
    return button
  }

  @objc private func openTracesFolder() { Task { @MainActor in actions.openTracesFolder() } }
  @objc private func chooseTracesFolder() { Task { @MainActor in actions.chooseTracesFolder() } }
  @objc private func loadSampleTraces() { Task { @MainActor in actions.loadSampleTraces() } }
  @objc private func toggleWatchFolder() { Task { @MainActor in actions.toggleWatchFolder() } }
  @objc private func showQuickstart() { Task { @MainActor in actions.showQuickstart() } }
  @objc private func finishOnboarding() { Task { @MainActor in actions.complete() } }
}
