import Foundation

public enum RefreshInterval: Double, CaseIterable, Identifiable, Sendable {
  case fiveSeconds = 5
  case tenSeconds = 10
  case thirtySeconds = 30
  case oneMinute = 60
  case twoMinutes = 120
  case fiveMinutes = 300

  public var id: Double { rawValue }

  public var label: String {
    switch self {
    case .fiveSeconds: return "5s"
    case .tenSeconds: return "10s"
    case .thirtySeconds: return "30s"
    case .oneMinute: return "1m"
    case .twoMinutes: return "2m"
    case .fiveMinutes: return "5m"
    }
  }

  public static func from(seconds: Double) -> RefreshInterval {
    Self.allCases.first { $0.rawValue == seconds } ?? .fiveSeconds
  }
}
