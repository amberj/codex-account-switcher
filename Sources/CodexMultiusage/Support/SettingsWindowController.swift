import AppKit
import CodexMultiusageCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  private let store: UsageStore
  private var window: NSWindow?

  init(store: UsageStore) {
    self.store = store
  }

  func show() {
    NSApp.setActivationPolicy(.regular)

    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let hostingController = NSHostingController(rootView: SettingsView(store: store))
    let settingsWindow = NSWindow(contentViewController: hostingController)
    settingsWindow.title = "Settings"
    settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
    settingsWindow.isReleasedWhenClosed = false
    settingsWindow.delegate = self
    settingsWindow.center()
    settingsWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window = settingsWindow
  }

  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === window else { return }
    NSApp.setActivationPolicy(.accessory)
  }
}
