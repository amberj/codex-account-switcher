import CodexMultiusageCore
import SwiftUI

struct AuthActivationView: View {
  @ObservedObject var store: UsageStore
  let row: AuthUsageRow
  let close: () -> Void

  @State private var isProcessing = false
  @State private var result: AuthSwitchResult?
  @State private var errorMessage: String?

  private var chosenFolder: URL {
    row.authFile.deletingLastPathComponent()
  }

  private var backupFolder: URL {
    chosenFolder.appendingPathComponent("backups", isDirectory: true)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let result {
        successContent(result)
      } else {
        confirmationContent
      }
    }
    .padding(24)
    .frame(width: 620)
  }

  private var confirmationContent: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Confirm Account Switch", systemImage: "person.crop.circle.badge.checkmark")
        .font(.title3)
        .fontWeight(.semibold)

      VStack(alignment: .leading, spacing: 12) {
        Text("Please confirm that you want to replace current \(store.defaultAuthFile.path) with the one from \(row.authFile.path)")

        Text("The replaced \(store.defaultAuthFile.path) will be backed up in \(backupFolder.path)/. The backed up file will be renamed with the timestamp when it was backed up e.g. auth.json-2026-05-12_18-30-00.backup")

        Text("Please click \"Continue\" to proceed, or \"Cancel\" to abort.")
      }
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)

      if let errorMessage {
        Text(errorMessage)
          .font(.callout)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Spacer()
        Button("Cancel") {
          close()
        }
        .disabled(isProcessing)

        Button("Continue") {
          continueSwitch()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isProcessing)
      }
    }
  }

  private func successContent(_ result: AuthSwitchResult) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Account Activated", systemImage: "checkmark.circle.fill")
        .font(.title3)
        .fontWeight(.semibold)
        .foregroundStyle(.green)

      Text("The selected auth.json has been copied to \(store.defaultAuthFile.path).")
        .textSelection(.enabled)

      Text("The previous auth.json was backed up at \(result.backupFile.path).")
        .textSelection(.enabled)

      Text("Restart all Codex CLI sessions and the Codex macOS app so the change takes effect.")
        .fontWeight(.semibold)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Spacer()
        Button("Done") {
          close()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
  }

  private func continueSwitch() {
    isProcessing = true
    errorMessage = nil

    do {
      result = try store.makeActive(row)
    } catch {
      errorMessage = error.localizedDescription
    }

    isProcessing = false
  }
}
