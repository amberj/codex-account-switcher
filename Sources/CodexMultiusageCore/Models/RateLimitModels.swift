import Foundation

public enum UsageBucket: String, CaseIterable, Sendable {
  case fiveHour
  case weekly
}

public struct UsageValues: Equatable, Sendable {
  public var fiveHourPercentRemaining: Int?
  public var weeklyPercentRemaining: Int?
  public var fiveHourResetAt: Date?
  public var weeklyResetAt: Date?

  public init(
    fiveHourPercentRemaining: Int? = nil,
    weeklyPercentRemaining: Int? = nil,
    fiveHourResetAt: Date? = nil,
    weeklyResetAt: Date? = nil
  ) {
    self.fiveHourPercentRemaining = fiveHourPercentRemaining
    self.weeklyPercentRemaining = weeklyPercentRemaining
    self.fiveHourResetAt = fiveHourResetAt
    self.weeklyResetAt = weeklyResetAt
  }

  public var title: String {
    "\(Self.format(fiveHourPercentRemaining))/\(Self.format(weeklyPercentRemaining))"
  }

  public var availabilityStatus: UsageAvailabilityStatus {
    let knownPercents = [fiveHourPercentRemaining, weeklyPercentRemaining]
      .compactMap { $0 }
      .map { min(max($0, 0), 100) }

    if knownPercents.contains(0) {
      return .empty
    }

    if knownPercents.contains(where: { $0 < 25 }) {
      return .low
    }

    return .available
  }

  public func detailLine(for bucket: UsageBucket, now: Date = Date(), timeZone: TimeZone = .current) -> String {
    let label: String
    let percent: Int?
    let resetAt: Date?

    switch bucket {
    case .fiveHour:
      label = "5H"
      percent = fiveHourPercentRemaining
      resetAt = fiveHourResetAt
    case .weekly:
      label = "Weekly"
      percent = weeklyPercentRemaining
      resetAt = weeklyResetAt
    }

    return "\(label): \(Self.format(percent)) (Resets \(Self.formatReset(resetAt, now: now, timeZone: timeZone)))"
  }

  public static func format(_ value: Int?) -> String {
    guard let value else {
      return "NA"
    }

    return "\(min(max(value, 0), 100))%"
  }

  private static func formatReset(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
    guard let date else {
      return "NA"
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "d MMM HH:mm"
    return formatter.string(from: date)
  }
}

public enum UsageAvailabilityStatus: Equatable, Sendable {
  case empty
  case low
  case available
}

public struct AuthUsageRow: Identifiable, Equatable, Sendable {
  public static let chatGPTLoginRequiredErrorMessage = "Invalid codex app-server response: failed to fetch codex rate limits"

  public var id: String { authFile.path }
  public let displayName: String
  public let authFile: URL
  public var usage: UsageValues?
  public var errorMessage: String?

  public var requiresChatGPTLogin: Bool {
    errorMessage?.localizedCaseInsensitiveContains("codex") == true
  }

  public init(displayName: String, authFile: URL, usage: UsageValues? = nil, errorMessage: String? = nil) {
    self.displayName = displayName
    self.authFile = authFile
    self.usage = usage
    self.errorMessage = errorMessage
  }
}
