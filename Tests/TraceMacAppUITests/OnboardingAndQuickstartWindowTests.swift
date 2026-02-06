import AppKit
import Foundation
import Testing
@testable import TraceMacAppUI

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

@MainActor
@Suite("Onboarding + Quickstart Windows", .serialized)
struct OnboardingAndQuickstartWindowTests {
  init() {
    _ = NSApplication.shared
  }

  @Test("Onboarding window renders expected buttons and invokes actions")
  func onboardingWindowButtonsInvokeActions() async throws {
    var calls: [String] = []

    let controller = OnboardingWindowController(
      actions: .init(
        openTracesFolder: { calls.append("open") },
        chooseTracesFolder: { calls.append("choose") },
        loadSampleTraces: { calls.append("sample") },
        toggleWatchFolder: { calls.append("watch") },
        showQuickstart: { calls.append("quickstart") },
        complete: { calls.append("done") }
      )
    )

    let contentView = try #require(controller.window?.contentViewController?.view)
    let buttons = allSubviews(of: NSButton.self, in: contentView)

    func button(_ title: String) throws -> NSButton {
      try #require(buttons.first(where: { $0.title == title }))
    }

    _ = try button("Open Traces Folder")
    _ = try button("Choose Traces Folder…")
    _ = try button("Load Sample Traces")
    _ = try button("Toggle Watch Folder")
    _ = try button("Instrument Your App (60s)…")
    let done = try button("Done")
    #expect(done.keyEquivalent == "\r")

    try button("Open Traces Folder").performClick(nil)
    await Task.yield()
    await Task.yield()
    #expect(calls.contains("open"))

    try button("Instrument Your App (60s)…").performClick(nil)
    await Task.yield()
    await Task.yield()
    #expect(calls.contains("quickstart"))

    try button("Done").performClick(nil)
    await Task.yield()
    await Task.yield()
    #expect(calls.contains("done"))
  }

  @Test("Quickstart window contains install snippet and Copy places it on pasteboard")
  func quickstartWindowContainsSnippetAndCopies() throws {
    let controller = QuickstartWindowController()

    let contentView = try #require(controller.window?.contentViewController?.view)
    let textView = try #require(allSubviews(of: NSTextView.self, in: contentView).first)
    #expect(textView.string.contains("import Terra"))
    #expect(textView.string.contains("Terra.installOpenTelemetry"))
    #expect(textView.string.contains("Terra.install(.init(privacy: .default))"))

    let copyButton = try #require(allSubviews(of: NSButton.self, in: contentView).first(where: { $0.title == "Copy" }))

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("placeholder", forType: .string)
    copyButton.performClick(nil)

    let copied = NSPasteboard.general.string(forType: .string)
    #expect(copied == textView.string)
  }
}

