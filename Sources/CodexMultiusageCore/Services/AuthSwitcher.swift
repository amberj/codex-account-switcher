import Foundation

public struct AuthSwitchResult: Equatable, Sendable {
  public let backupFile: URL
  public let activatedAuthFile: URL

  public init(backupFile: URL, activatedAuthFile: URL) {
    self.backupFile = backupFile
    self.activatedAuthFile = activatedAuthFile
  }
}

public struct AuthSwitcher {
  public enum SwitchError: LocalizedError, Equatable {
    case missingCurrentAuth(String)
    case missingChosenAuth(String)
    case chosenAuthMatchesCurrent(String)

    public var errorDescription: String? {
      switch self {
      case .missingCurrentAuth(let path):
        "Current Codex auth.json does not exist at \(path)."
      case .missingChosenAuth(let path):
        "Chosen auth.json does not exist at \(path)."
      case .chosenAuthMatchesCurrent(let path):
        "Chosen auth.json is already the active file at \(path)."
      }
    }
  }

  private let fileManager: FileManager
  private let now: @Sendable () -> Date

  public init(fileManager: FileManager = .default, now: @escaping @Sendable () -> Date = { Date() }) {
    self.fileManager = fileManager
    self.now = now
  }

  public func switchAuth(currentAuthFile: URL, chosenAuthFile: URL) throws -> AuthSwitchResult {
    let currentAuthFile = currentAuthFile.resolvingSymlinksInPath()
    let chosenAuthFile = chosenAuthFile.resolvingSymlinksInPath()

    guard fileManager.fileExists(atPath: currentAuthFile.path) else {
      throw SwitchError.missingCurrentAuth(currentAuthFile.path)
    }

    guard fileManager.fileExists(atPath: chosenAuthFile.path) else {
      throw SwitchError.missingChosenAuth(chosenAuthFile.path)
    }

    guard currentAuthFile.path != chosenAuthFile.path else {
      throw SwitchError.chosenAuthMatchesCurrent(chosenAuthFile.path)
    }

    let accountFolder = chosenAuthFile.deletingLastPathComponent()
    let backupFolder = accountFolder.appendingPathComponent("backups", isDirectory: true)
    let backupFile = backupFolder.appendingPathComponent("auth.json-\(Self.timestampFormatter.string(from: now())).backup")

    try fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)
    try fileManager.copyItem(at: currentAuthFile, to: backupFile)

    let temporaryReplacement = currentAuthFile
      .deletingLastPathComponent()
      .appendingPathComponent(".auth.json-\(UUID().uuidString).tmp")

    do {
      try fileManager.copyItem(at: chosenAuthFile, to: temporaryReplacement)
      _ = try fileManager.replaceItemAt(currentAuthFile, withItemAt: temporaryReplacement)
    } catch {
      try? fileManager.removeItem(at: temporaryReplacement)
      throw error
    }

    return AuthSwitchResult(backupFile: backupFile, activatedAuthFile: chosenAuthFile)
  }

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter
  }()
}
