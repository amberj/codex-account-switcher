import AppKit
import CodexMultiusageCore
import SwiftUI

struct AuthLoginView: View {
  @ObservedObject var store: UsageStore
  let row: AuthUsageRow
  let close: () -> Void

  @State private var session: CodexChatGPTLoginSession?
  @State private var authURL: URL?
  @State private var isStarting = true
  @State private var isWaitingForCompletion = false
  @State private var didComplete = false
  @State private var errorMessage: String?
  @State private var copiedURL = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Login to ChatGPT", systemImage: didComplete ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
        .font(.title3)
        .fontWeight(.semibold)
        .foregroundStyle(didComplete ? .green : .primary)

      Text(row.displayName)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)

      if isStarting {
        ProgressView("Starting Codex app-server login...")
      } else if let authURL {
        VStack(alignment: .leading, spacing: 10) {
          Link(authURL.absoluteString, destination: authURL)
            .textSelection(.enabled)
            .lineLimit(3)

          HStack(spacing: 8) {
            Button(copiedURL ? "Copied" : "Copy URL") {
              copyURL(authURL)
            }

            Button("Open URL in Browser") {
              NSWorkspace.shared.open(authURL)
            }
            .keyboardShortcut(.defaultAction)
          }
        }
      }

      if isWaitingForCompletion {
        ProgressView("Waiting for OAuth completion...")
      }

      if didComplete {
        Text("Login completed. The auth.json in \(row.authFile.deletingLastPathComponent().path) was updated.")
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.callout)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }

      HStack {
        Spacer()
        Button(didComplete || errorMessage != nil ? "Done" : "Cancel") {
          if !didComplete {
            session?.cancel()
          }
          close()
        }
      }
    }
    .padding(24)
    .frame(width: 640)
    .task {
      await startLogin()
    }
  }

  private func startLogin() async {
    guard session == nil, authURL == nil else {
      return
    }

    isStarting = true
    errorMessage = nil

    do {
      let session = try await store.startChatGPTLogin(for: row)
      self.session = session
      authURL = session.authURL
      isStarting = false
      isWaitingForCompletion = true

      try await session.waitForCompletion()
      didComplete = true
      isWaitingForCompletion = false
      store.refreshUsageStatus()
    } catch {
      isStarting = false
      isWaitingForCompletion = false
      errorMessage = error.localizedDescription
    }
  }

  private func copyURL(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
    copiedURL = true
  }
}
