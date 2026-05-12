import Foundation

public struct AuthFolderScanner {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func authFiles(in chosenFolder: URL) throws -> [AuthUsageRow] {
    let children = try fileManager.contentsOfDirectory(
      at: chosenFolder,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    return try children.compactMap { child in
      let values = try child.resourceValues(forKeys: [.isDirectoryKey])
      guard values.isDirectory == true else {
        return nil
      }

      let authFile = child.appendingPathComponent("auth.json", isDirectory: false)
      guard fileManager.fileExists(atPath: authFile.path) else {
        return nil
      }

      return AuthUsageRow(displayName: child.lastPathComponent, authFile: authFile)
    }
    .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }
}
