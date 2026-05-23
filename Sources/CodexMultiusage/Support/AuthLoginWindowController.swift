import AppKit
import CodexMultiusageCore
import SwiftUI

@MainActor
final class AuthLoginWindowController {
  private let store: UsageStore
  private var window: NSWindow?

  init(store: UsageStore) {
    self.store = store
  }

  func show(for row: AuthUsageRow) {
    window?.close()

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Login to ChatGPT"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: AuthLoginView(store: store, row: row) { [weak self] in
        self?.window?.close()
      }
    )
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
  }
}
