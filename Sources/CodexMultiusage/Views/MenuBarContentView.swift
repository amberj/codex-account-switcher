import AppKit
import CodexMultiusageCore
import SwiftUI

struct MenuBarContentView: View {
  @ObservedObject var store: UsageStore
  let makeActive: (AuthUsageRow) -> Void
  let showSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      defaultStatus

      if store.rows.isEmpty {
        Divider()
        Text(store.hasChosenFolder ? "No child auth files" : "Choose folder in Settings")
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(store.rows.enumerated()), id: \.element.id) { _, row in
          Divider()
          UsageRowView(row: row, makeActive: makeActive)
        }
      }

      if let message = store.lastRefreshMessage {
        Divider()
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Divider()

      LastRefreshedText(lastRefreshedAt: store.lastRefreshedAt)

      Button("Refresh Now") {
        store.refreshNow()
      }
      .disabled(store.isCheckingFolderStatuses)

      Button("Settings") {
        showSettings()
      }

      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
    .frame(minWidth: 300)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }

  private var defaultStatus: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        StatusIcon(status: store.defaultUsage.availabilityStatus)

        Text("Currently active auth.json in Codex")
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(1)
      }

      if store.defaultAuthExists {
        UsageDetailLines(usage: store.defaultUsage)
      } else {
        Text("Codex not installed in default location")
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .lineLimit(2)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
  }
}

private struct LastRefreshedText: View {
  let lastRefreshedAt: Date?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      Text(text(at: context.date))
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }

  private func text(at now: Date) -> String {
    let lastRefreshedAt = lastRefreshedAt ?? now
    let secondsAgo = max(0, Int(now.timeIntervalSince(lastRefreshedAt)))
    return "Last refreshed: \(secondsAgo) seconds ago"
  }
}

private struct UsageRowView: View {
  let row: AuthUsageRow
  let makeActive: (AuthUsageRow) -> Void

  var body: some View {
    let usage = row.usage ?? UsageValues()

    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        HStack(spacing: 6) {
          StatusIcon(status: usage.availabilityStatus)

          Text(row.displayName)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button("Make active") {
          makeActive(row)
        }
        .font(.system(size: 12))
      }

      UsageDetailLines(usage: usage)

      if let errorMessage = row.errorMessage {
        Text(errorMessage)
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .lineLimit(2)
      }
    }
  }
}

private struct StatusIcon: View {
  let status: UsageAvailabilityStatus

  var body: some View {
    switch status {
    case .empty:
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
    case .low:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
    case .available:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    }
  }
}

private struct UsageDetailLines: View {
  let usage: UsageValues

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(usage.detailLine(for: .fiveHour))
      Text(usage.detailLine(for: .weekly))
    }
    .font(.system(size: 12))
    .foregroundStyle(.secondary)
    .monospacedDigit()
  }
}
