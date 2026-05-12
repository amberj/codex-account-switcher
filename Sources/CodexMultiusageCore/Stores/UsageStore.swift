import Foundation

@MainActor
public final class UsageStore: ObservableObject {
  private enum DefaultsKey {
    static let chosenFolderPath = "chosenFolderPath"
    static let refreshIntervalSeconds = "refreshIntervalSeconds"
    static let startOnLogin = "startOnLogin"
  }

  @Published public private(set) var defaultUsage = UsageValues()
  @Published public private(set) var rows: [AuthUsageRow] = []
  @Published public private(set) var isRefreshing = false
  @Published public private(set) var isCheckingFolderStatuses = false
  @Published public private(set) var defaultAuthExists = false
  @Published public private(set) var lastRefreshedAt: Date?
  @Published public private(set) var lastRefreshMessage: String?
  @Published public var chosenFolderPath: String {
    didSet {
      defaults.set(chosenFolderPath, forKey: DefaultsKey.chosenFolderPath)
      restartTimer()
    }
  }
  @Published public var refreshInterval: RefreshInterval {
    didSet {
      defaults.set(refreshInterval.rawValue, forKey: DefaultsKey.refreshIntervalSeconds)
      restartTimer()
    }
  }
  @Published public var startOnLogin: Bool {
    didSet {
      defaults.set(startOnLogin, forKey: DefaultsKey.startOnLogin)
      startOnLoginHandler(startOnLogin)
    }
  }

  public let defaultAuthFile: URL
  private let scanner: AuthFolderScanner
  private let authSwitcher: AuthSwitcher
  private let client: CodexAppServerClient
  private let defaults: UserDefaults
  private let startOnLoginHandler: @MainActor (Bool) -> Void
  private var timer: Timer?
  private var refreshTask: Task<Void, Never>?

  public init(
    scanner: AuthFolderScanner = AuthFolderScanner(),
    authSwitcher: AuthSwitcher = AuthSwitcher(),
    client: CodexAppServerClient = CodexAppServerClient(),
    defaults: UserDefaults = .standard,
    defaultAuthFile: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/auth.json"),
    startOnLoginHandler: @escaping @MainActor (Bool) -> Void = { _ in }
  ) {
    self.scanner = scanner
    self.authSwitcher = authSwitcher
    self.client = client
    self.defaults = defaults
    self.defaultAuthFile = defaultAuthFile
    self.startOnLoginHandler = startOnLoginHandler
    self.chosenFolderPath = defaults.string(forKey: DefaultsKey.chosenFolderPath) ?? ""
    self.refreshInterval = RefreshInterval.from(seconds: defaults.double(forKey: DefaultsKey.refreshIntervalSeconds))
    self.startOnLogin = defaults.bool(forKey: DefaultsKey.startOnLogin)
    updateDefaultAuthStatus()
    restartTimer()
  }

  deinit {
    timer?.invalidate()
    refreshTask?.cancel()
  }

  public var hasChosenFolder: Bool {
    !chosenFolderPath.isEmpty
  }

  public func updateChosenFolder(_ folder: URL) {
    chosenFolderPath = folder.path
    refreshUsageStatus()
  }

  public func refreshNow() {
    startRefresh(disablesRefreshButtonDuringFolderCheck: true)
  }

  public func refreshUsageStatus() {
    startRefresh(disablesRefreshButtonDuringFolderCheck: false)
  }

  public func makeActive(_ row: AuthUsageRow) throws -> AuthSwitchResult {
    let result = try authSwitcher.switchAuth(currentAuthFile: defaultAuthFile, chosenAuthFile: row.authFile)
    updateDefaultAuthStatus()
    refreshUsageStatus()
    return result
  }

  private func startRefresh(disablesRefreshButtonDuringFolderCheck: Bool) {
    refreshTask?.cancel()
    refreshTask = Task {
      await refresh(disablesRefreshButtonDuringFolderCheck: disablesRefreshButtonDuringFolderCheck)
    }
  }

  private func restartTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: refreshInterval.rawValue, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refreshUsageStatus()
      }
    }
  }

  private func updateDefaultAuthStatus() {
    defaultAuthExists = FileManager.default.fileExists(atPath: defaultAuthFile.path)
  }

  private func refresh(disablesRefreshButtonDuringFolderCheck: Bool) async {
    guard !isRefreshing else {
      return
    }

    isRefreshing = true
    updateDefaultAuthStatus()
    defer {
      lastRefreshedAt = Date()
      isRefreshing = false
    }

    if defaultAuthExists {
      do {
        defaultUsage = try await client.readUsage(authFile: defaultAuthFile)
      } catch {
        defaultUsage = UsageValues()
        lastRefreshMessage = error.localizedDescription
      }
    } else {
      defaultUsage = UsageValues()
      lastRefreshMessage = "Codex not installed in default location."
    }

    guard hasChosenFolder else {
      rows = []
      return
    }

    do {
      if disablesRefreshButtonDuringFolderCheck {
        isCheckingFolderStatuses = true
      }
      defer { isCheckingFolderStatuses = false }

      let authRows = try scanner.authFiles(in: URL(fileURLWithPath: chosenFolderPath, isDirectory: true))
      var refreshedRows: [AuthUsageRow] = []
      for row in authRows {
        do {
          let usage = try await client.readUsage(authFile: row.authFile)
          refreshedRows.append(AuthUsageRow(displayName: row.displayName, authFile: row.authFile, usage: usage))
        } catch {
          refreshedRows.append(AuthUsageRow(displayName: row.displayName, authFile: row.authFile, errorMessage: error.localizedDescription))
        }
      }
      rows = refreshedRows
      lastRefreshMessage = nil
    } catch {
      rows = []
      lastRefreshMessage = error.localizedDescription
    }
  }
}
