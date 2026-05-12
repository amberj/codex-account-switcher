import AppKit
import CodexMultiusageCore
import SwiftUI

@MainActor
final class AuthActivationWindowController: NSObject, NSWindowDelegate {
  private let store: UsageStore
  private var window: NSWindow?

  init(store: UsageStore) {
    self.store = store
  }

  func show(for row: AuthUsageRow) {
    NSApp.setActivationPolicy(.regular)

    let hostingController = NSHostingController(
      rootView: AuthActivationView(
        store: store,
        row: row,
        close: { [weak self] in
          self?.close()
        }
      )
    )

    if let window {
      window.contentViewController = hostingController
      window.title = "Make Account Active"
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let activationWindow = NSWindow(contentViewController: hostingController)
    activationWindow.title = "Make Account Active"
    activationWindow.styleMask = [.titled, .closable, .miniaturizable]
    activationWindow.isReleasedWhenClosed = false
    activationWindow.delegate = self
    activationWindow.center()
    activationWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window = activationWindow
  }

  func close() {
    window?.close()
  }

  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === window else { return }
    NSApp.setActivationPolicy(.accessory)
  }
}
