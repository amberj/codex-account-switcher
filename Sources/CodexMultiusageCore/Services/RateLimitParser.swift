import Foundation

public enum RateLimitParserError: Error, LocalizedError {
  case invalidJSON

  public var errorDescription: String? {
    switch self {
    case .invalidJSON:
      return "Codex app-server returned invalid JSON."
    }
  }
}

public struct RateLimitParser: Sendable {
  public init() {}

  public func parse(_ data: Data) throws -> UsageValues {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let root = object as? [String: Any] else {
      throw RateLimitParserError.invalidJSON
    }

    var values = UsageValues()
    for dictionary in Self.collectDictionaries(root) {
      guard let bucket = Self.bucket(in: dictionary),
            let percent = Self.remainingPercent(in: dictionary) else {
        continue
      }

      switch bucket {
      case .fiveHour:
        values.fiveHourPercentRemaining = percent
        values.fiveHourResetAt = Self.resetDate(in: dictionary)
      case .weekly:
        values.weeklyPercentRemaining = percent
        values.weeklyResetAt = Self.resetDate(in: dictionary)
      }
    }

    return values
  }

  private static func collectDictionaries(_ value: Any) -> [[String: Any]] {
    var dictionaries: [[String: Any]] = []

    if let dictionary = value as? [String: Any] {
      dictionaries.append(dictionary)
      for child in dictionary.values {
        dictionaries.append(contentsOf: collectDictionaries(child))
      }
    } else if let array = value as? [Any] {
      for child in array {
        dictionaries.append(contentsOf: collectDictionaries(child))
      }
    }

    return dictionaries
  }

  private static func bucket(in dictionary: [String: Any]) -> UsageBucket? {
    if let windowDurationMins = numericValue(forAnyOf: ["windowDurationMins", "window_duration_mins"], in: dictionary) {
      if Int(windowDurationMins) == 300 {
        return .fiveHour
      }

      if Int(windowDurationMins) == 10_080 {
        return .weekly
      }
    }

    let searchable = dictionary
      .filter { key, _ in
        ["name", "window", "period", "type", "bucket", "label", "id"].contains(key.lowercased())
      }
      .map { _, value in String(describing: value).lowercased() }
      .joined(separator: " ")

    if searchable.contains("5h")
      || searchable.contains("5 hour")
      || searchable.contains("5-hour")
      || searchable.contains("five hour") {
      return .fiveHour
    }

    if searchable.contains("week") || searchable.contains("weekly") {
      return .weekly
    }

    return nil
  }

  private static func remainingPercent(in dictionary: [String: Any]) -> Int? {
    if let explicit = numericValue(forAnyOf: ["remainingPercent", "remaining_percent", "percentRemaining", "percent_remaining"], in: dictionary) {
      return Int(explicit.rounded())
    }

    if let usedPercent = numericValue(forAnyOf: ["usedPercent", "used_percent", "usagePercent", "usage_percent"], in: dictionary) {
      return Int((100 - usedPercent).rounded())
    }

    if let remaining = numericValue(forAnyOf: ["remaining", "remainingTokens", "remaining_tokens"], in: dictionary),
       let limit = numericValue(forAnyOf: ["limit", "max", "total"], in: dictionary),
       limit > 0 {
      return Int(((remaining / limit) * 100).rounded())
    }

    if let used = numericValue(forAnyOf: ["used", "usage", "consumed"], in: dictionary),
       let limit = numericValue(forAnyOf: ["limit", "max", "total"], in: dictionary),
       limit > 0 {
      return Int(((1 - (used / limit)) * 100).rounded())
    }

    return nil
  }

  private static func resetDate(in dictionary: [String: Any]) -> Date? {
    guard let value = value(forAnyOf: ["resetsAt", "resets_at", "resetAt", "reset_at"], in: dictionary) else {
      return nil
    }

    if let number = value as? NSNumber {
      let seconds = number.doubleValue
      return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
    }

    if let string = value as? String {
      if let seconds = Double(string) {
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
      }

      let isoFormatter = ISO8601DateFormatter()
      isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = isoFormatter.date(from: string) {
        return date
      }

      isoFormatter.formatOptions = [.withInternetDateTime]
      return isoFormatter.date(from: string)
    }

    return nil
  }

  private static func numericValue(forAnyOf names: [String], in dictionary: [String: Any]) -> Double? {
    guard let value = value(forAnyOf: names, in: dictionary) else {
      return nil
    }

    if let number = value as? NSNumber {
      return number.doubleValue
    }

    if let string = value as? String, let double = Double(string) {
      return double
    }

    return nil
  }

  private static func value(forAnyOf names: [String], in dictionary: [String: Any]) -> Any? {
    let normalizedNames = Set(names.map { $0.lowercased() })
    for (key, value) in dictionary where normalizedNames.contains(key.lowercased()) {
      return value
    }

    return nil
  }
}
