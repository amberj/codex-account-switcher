import Foundation
import CodexMultiusageCore

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() {
    throw CheckFailure(message)
  }
}

struct CheckFailure: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

let checkISODateFormatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()

func checkDate(_ isoString: String) -> Date {
  guard let date = checkISODateFormatter.date(from: isoString) else {
    fatalError("Invalid check date: \(isoString)")
  }

  return date
}

func checkUsageFormatting() throws {
  try expect(
    UsageValues(fiveHourPercentRemaining: nil, weeklyPercentRemaining: 41).title == "NA/41%",
    "missing 5H bucket should format as NA"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: 72, weeklyPercentRemaining: nil).title == "72%/NA",
    "missing weekly bucket should format as NA"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: -4, weeklyPercentRemaining: 120).title == "0%/100%",
    "percent display should clamp to 0...100"
  )

  let timeZone = TimeZone(secondsFromGMT: 19_800)!
  let usage = UsageValues(
    fiveHourPercentRemaining: 36,
    weeklyPercentRemaining: 90,
    fiveHourResetAt: checkDate("2026-05-12T08:54:00Z"),
    weeklyResetAt: checkDate("2026-05-18T08:50:00Z")
  )
  let now = checkDate("2026-05-12T05:00:00Z")
  try expect(
    usage.detailLine(for: .fiveHour, now: now, timeZone: timeZone) == "5H: 36% (Resets 14:24)",
    "5H detail line should include same-day reset time"
  )
  try expect(
    usage.detailLine(for: .weekly, now: now, timeZone: timeZone) == "Weekly: 90% (Resets 18 May 14:20)",
    "weekly detail line should include reset date and time"
  )
  try expect(
    UsageValues(weeklyPercentRemaining: 0).detailLine(for: .fiveHour, now: now, timeZone: timeZone) == "5H: NA (Resets NA)",
    "missing 5H detail line should format percent and reset as NA"
  )
}

func checkUsageStatus() throws {
  try expect(
    UsageValues(fiveHourPercentRemaining: 0, weeklyPercentRemaining: 100).availabilityStatus == .empty,
    "0% 5H quota should be marked empty"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: 100, weeklyPercentRemaining: 0).availabilityStatus == .empty,
    "0% weekly quota should be marked empty"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: 24, weeklyPercentRemaining: 100).availabilityStatus == .low,
    "5H quota under 25% should be marked low"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: 100, weeklyPercentRemaining: 24).availabilityStatus == .low,
    "weekly quota under 25% should be marked low"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: nil, weeklyPercentRemaining: 24).availabilityStatus == .low,
    "NA 5H quota should not hide a low weekly quota"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: nil, weeklyPercentRemaining: 100).availabilityStatus == .available,
    "NA 5H quota should be ignored when remaining known quotas are healthy"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: 25, weeklyPercentRemaining: nil).availabilityStatus == .available,
    "25% should not be treated as under 25%"
  )
  try expect(
    UsageValues(fiveHourPercentRemaining: nil, weeklyPercentRemaining: nil).availabilityStatus == .available,
    "all-NA quotas should not produce a warning or empty status"
  )
}

func checkLoginRequiredStatus() throws {
  try expect(
    AuthUsageRow(
      displayName: "account-a",
      authFile: URL(fileURLWithPath: "/tmp/account-a/auth.json"),
      errorMessage: "Invalid codex app-server response: failed to fetch codex rate limits"
    ).requiresChatGPTLogin,
    "accounts with failed codex rate-limit fetches should expose Login"
  )

  try expect(
    AuthUsageRow(
      displayName: "account-a",
      authFile: URL(fileURLWithPath: "/tmp/account-a/auth.json"),
      errorMessage: "Invalid codex app-server response: failed to fetch codex rate limits\nstatus: 401"
    ).requiresChatGPTLogin,
    "accounts with failed codex rate-limit fetches plus diagnostics should still expose Login"
  )

  try expect(
    AuthUsageRow(
      displayName: "account-c",
      authFile: URL(fileURLWithPath: "/tmp/account-c/auth.json"),
      errorMessage: "Invalid codex app-server response: codex account requires login"
    ).requiresChatGPTLogin,
    "accounts with any codex app-server auth error should expose Login"
  )

  try expect(
    AuthUsageRow(
      displayName: "account-b",
      authFile: URL(fileURLWithPath: "/tmp/account-b/auth.json"),
      errorMessage: "Timed out waiting for codex app-server."
    ).requiresChatGPTLogin,
    "accounts with any codex error should expose Login"
  )

  try expect(
    !AuthUsageRow(
      displayName: "account-d",
      authFile: URL(fileURLWithPath: "/tmp/account-d/auth.json"),
      errorMessage: "Network request failed."
    ).requiresChatGPTLogin,
    "accounts with unrelated non-codex errors should not expose Login"
  )
}

func checkAuthFolderScanner() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let child = root.appendingPathComponent("account-a", isDirectory: true)
  let nested = child.appendingPathComponent("nested", isDirectory: true)
  let directFile = child.appendingPathComponent("auth.json")
  let nestedFile = nested.appendingPathComponent("auth.json")
  let rootFile = root.appendingPathComponent("auth.json")

  try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
  try Data("{}".utf8).write(to: directFile)
  try Data("{}".utf8).write(to: nestedFile)
  try Data("{}".utf8).write(to: rootFile)

  let results = try AuthFolderScanner().authFiles(in: root)
  try expect(results.map(\.displayName) == ["account-a"], "scanner should include only direct child folder names")
  let resultPaths = results.map { $0.authFile.resolvingSymlinksInPath().path }
  let expectedPaths = [directFile.resolvingSymlinksInPath().path]
  try expect(resultPaths == expectedPaths, "scanner should include only direct child auth files")
}

func checkAuthSwitcher() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
  let accountFolder = root.appendingPathComponent("accounts/account-a", isDirectory: true)
  let currentAuth = codexHome.appendingPathComponent("auth.json")
  let chosenAuth = accountFolder.appendingPathComponent("auth.json")

  try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: accountFolder, withIntermediateDirectories: true)
  try Data(#"{"current":true}"#.utf8).write(to: currentAuth)
  try Data(#"{"chosen":true}"#.utf8).write(to: chosenAuth)

  let switcher = AuthSwitcher(now: {
    checkDate("2026-05-12T13:00:00Z")
  })
  let result = try switcher.switchAuth(currentAuthFile: currentAuth, chosenAuthFile: chosenAuth)

  try expect(
    result.backupFile.deletingLastPathComponent().path == accountFolder.appendingPathComponent("backups", isDirectory: true).path,
    "auth switcher should place backups under the chosen account folder"
  )
  try expect(
    result.backupFile.lastPathComponent == "auth.json-2026-05-12_18-30-00.backup",
    "backup filename should include the local timestamp"
  )
  try expect(
    try String(contentsOf: result.backupFile, encoding: .utf8) == #"{"current":true}"#,
    "backup should contain the previous current auth file"
  )
  try expect(
    try String(contentsOf: currentAuth, encoding: .utf8) == #"{"chosen":true}"#,
    "current auth should be replaced by the chosen auth file"
  )
}

func checkRateLimitParser() throws {
  let explicitData = Data("""
  {
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
      "rateLimits": [
        { "name": "5h", "remainingPercent": 72, "resetsAt": "2026-05-12T04:00:00Z" },
        { "name": "weekly", "remainingPercent": 41, "resetsAt": "2026-05-18T00:00:00Z" }
      ]
    }
  }
  """.utf8)
  try expect(
    try RateLimitParser().parse(explicitData) == UsageValues(
      fiveHourPercentRemaining: 72,
      weeklyPercentRemaining: 41,
      fiveHourResetAt: checkDate("2026-05-12T04:00:00Z"),
      weeklyResetAt: checkDate("2026-05-18T00:00:00Z")
    ),
    "parser should read explicit remaining percent values"
  )

  let calculatedData = Data("""
  {
    "result": {
      "limits": [
        { "window": "5 hour", "remaining": 20, "limit": 40 },
        { "window": "week", "used": 25, "limit": 100 }
      ]
    }
  }
  """.utf8)
  try expect(
    try RateLimitParser().parse(calculatedData) == UsageValues(fiveHourPercentRemaining: 50, weeklyPercentRemaining: 75),
    "parser should calculate remaining percent from remaining/limit and used/limit"
  )

  let missingData = Data("""
  { "result": { "rateLimits": [{ "name": "weekly", "remainingPercent": 12 }] } }
  """.utf8)
  try expect(
    try RateLimitParser().parse(missingData) == UsageValues(fiveHourPercentRemaining: nil, weeklyPercentRemaining: 12),
    "parser should leave absent buckets nil"
  )

  let appServerData = Data("""
  {
    "id": 2,
    "result": {
      "rateLimits": {
        "primary": { "usedPercent": 49, "windowDurationMins": 300, "resetsAt": 1778541883 },
        "secondary": { "usedPercent": 8, "windowDurationMins": 10080, "resetsAt": 1779128683 }
      }
    }
  }
  """.utf8)
  try expect(
    try RateLimitParser().parse(appServerData) == UsageValues(
      fiveHourPercentRemaining: 51,
      weeklyPercentRemaining: 92,
      fiveHourResetAt: Date(timeIntervalSince1970: 1_778_541_883),
      weeklyResetAt: Date(timeIntervalSince1970: 1_779_128_683)
    ),
    "parser should read current app-server primary and secondary rate limit shape"
  )
}

func checkChatGPTLoginProtocol() throws {
  let clientSourcePath = "Sources/CodexMultiusageCore/Services/CodexAppServerClient.swift"
  let clientSource = try String(contentsOfFile: clientSourcePath, encoding: .utf8)

  try expect(
    clientSource.contains(#""method":"account/login/start""#),
    "ChatGPT login should start through codex app-server account/login/start"
  )
  try expect(
    clientSource.contains(#""params":{"type":"chatgpt"}"#),
    "ChatGPT login should use the codex app-server managed browser OAuth flow"
  )
  try expect(
    clientSource.contains(#""account/login/completed""#),
    "ChatGPT login should listen for OAuth completion notifications"
  )
  try expect(
    clientSource.contains(#"environment["CODEX_HOME"] = authFolder.path"#),
    "ChatGPT login should write auth.json into the selected account folder"
  )
  try expect(
    clientSource.contains(#"authFolder.appendingPathComponent("auth.json""#),
    "ChatGPT login should verify auth.json was written to the selected account folder"
  )
}

func checkMenuBarPresentation() throws {
  let appSourcePath = "Sources/CodexMultiusage/App/CodexMultiusageApp.swift"
  let appSource = try String(contentsOfFile: appSourcePath, encoding: .utf8)

  try expect(
    appSource.contains(".menuBarExtraStyle(.window)"),
    "menu bar extra should use window style so Refresh Now keeps the content visible"
  )
  try expect(
    !appSource.contains(".menuBarExtraStyle(.menu)"),
    "menu style dismisses the menu bar extra when Refresh Now is clicked"
  )

  let menuSourcePath = "Sources/CodexMultiusage/Views/MenuBarContentView.swift"
  let menuSource = try String(contentsOfFile: menuSourcePath, encoding: .utf8)

  try expect(
    menuSource.contains("StatusIcon(status: store.defaultUsage.availabilityStatus)"),
    "Default Codex row should render the same usage status icon as chosen folders"
  )
  try expect(
    menuSource.contains(".disabled(store.isCheckingFolderStatuses)"),
    "Refresh Now should only be disabled while a manual all-folder status check is running"
  )
  try expect(
    !menuSource.contains(".disabled(store.isRefreshing)"),
    "Refresh Now should not be disabled by broad automatic refresh state"
  )
  try expect(
    menuSource.contains("Button(\"Make active\")"),
    "each chosen folder row should expose a Make active button"
  )
  try expect(
    menuSource.contains("Button(\"Re-login\")"),
    "rows with failed ChatGPT rate-limit fetches should expose a Re-login button"
  )
  try expect(
    menuSource.contains("row.requiresChatGPTLogin"),
    "Login button should be limited to the codex rate-limit auth failure"
  )
  try expect(
    menuSource.contains("login(row)"),
    "Login button should delegate account-specific login handling"
  )
  try expect(
    menuSource.contains("ErrorMessageLine(row: row, login: login)"),
    "Login button should render beside the error message instead of competing with the row title"
  )
}

do {
  try checkUsageFormatting()
  try checkUsageStatus()
  try checkLoginRequiredStatus()
  try checkAuthFolderScanner()
  try checkAuthSwitcher()
  try checkRateLimitParser()
  try checkChatGPTLoginProtocol()
  try checkMenuBarPresentation()
  print("All CodexMultiusageCore checks passed.")
} catch {
  fputs("Check failed: \(error)\n", stderr)
  exit(1)
}
