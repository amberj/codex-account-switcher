import AppKit
import CodexMultiusageCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: UsageStore

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Codex Multiusage")
        .font(.title2)
        .fontWeight(.semibold)

      defaultAuthSection
      folderSection
      refreshSection
      Toggle("Start on login", isOn: $store.startOnLogin)

      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(width: 520, height: 320)
  }

  private var defaultAuthSection: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: store.defaultAuthExists ? "checkmark.circle.fill" : "xmark.octagon.fill")
        .foregroundStyle(store.defaultAuthExists ? .green : .red)
      VStack(alignment: .leading, spacing: 2) {
        Text("Default Codex auth")
          .font(.headline)
        if store.defaultAuthExists {
          Text(store.defaultAuthFile.path)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else {
          Text("Codex not installed in default location.")
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }
    }
  }

  private var folderSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Auth folder")
        .font(.headline)

      HStack(spacing: 8) {
        Text(store.chosenFolderPath.isEmpty ? "No folder selected" : store.chosenFolderPath)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(store.chosenFolderPath.isEmpty ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)

        Button("Browse") {
          browseForFolder()
        }
      }
    }
  }

  private var refreshSection: some View {
    Picker("Refresh", selection: $store.refreshInterval) {
      ForEach(RefreshInterval.allCases) { interval in
        Text(interval.label).tag(interval)
      }
    }
    .pickerStyle(.segmented)
  }

  private func browseForFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"

    if panel.runModal() == .OK, let url = panel.url {
      store.updateChosenFolder(url)
    }
  }
}
