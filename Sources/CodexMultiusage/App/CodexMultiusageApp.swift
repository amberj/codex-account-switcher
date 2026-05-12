import AppKit
import CodexMultiusageCore
import ServiceManagement
import SwiftUI

@main
struct CodexMultiusageApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var store: UsageStore
  private let settingsWindowController: SettingsWindowController
  private let authActivationWindowController: AuthActivationWindowController

  init() {
    let usageStore = UsageStore(startOnLoginHandler: Self.updateStartOnLogin)
    let settingsController = SettingsWindowController(store: usageStore)
    let activationController = AuthActivationWindowController(store: usageStore)
    _store = StateObject(wrappedValue: usageStore)
    settingsWindowController = settingsController
    authActivationWindowController = activationController

    Task { @MainActor in
      usageStore.refreshUsageStatus()
      if !usageStore.hasChosenFolder {
        settingsController.show()
      }
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(
        store: store,
        makeActive: { row in
          NSApp.keyWindow?.close()
          authActivationWindowController.show(for: row)
        },
        showSettings: {
          settingsWindowController.show()
        }
      )
    } label: {
      Text(store.defaultUsage.title)
        .monospacedDigit()
    }
    .menuBarExtraStyle(.window)
  }

  @MainActor
  private static func updateStartOnLogin(_ enabled: Bool) {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
      } catch {
        NSLog("Unable to update login item: \(error.localizedDescription)")
      }
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}
