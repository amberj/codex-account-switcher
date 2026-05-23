import Foundation

public enum CodexAppServerClientError: Error, LocalizedError {
  case authFileMissing(URL)
  case launchFailed(String)
  case timedOut
  case emptyResponse
  case invalidResponse(String)
  case loginFailed(String)

  public var errorDescription: String? {
    switch self {
    case .authFileMissing(let url):
      return "Auth file not found: \(url.path)"
    case .launchFailed(let message):
      return "Unable to launch codex app-server: \(message)"
    case .timedOut:
      return "Timed out waiting for codex app-server."
    case .emptyResponse:
      return "Codex app-server returned no response."
    case .invalidResponse(let message):
      return "Invalid codex app-server response: \(message)"
    case .loginFailed(let message):
      return "ChatGPT login failed: \(message)"
    }
  }
}

public final class CodexChatGPTLoginSession: @unchecked Sendable {
  public let authURL: URL
  public let loginId: String

  private let process: Process
  private let stdin: Pipe
  private let stdout: Pipe
  private let stderr: Pipe
  private let authFile: URL
  private let stateQueue = DispatchQueue(label: "CodexChatGPTLoginSession.state")
  private var completion: Result<Void, Error>?
  private var continuation: CheckedContinuation<Void, Error>?
  private var isCleanedUp = false

  fileprivate init(authURL: URL, loginId: String, process: Process, stdin: Pipe, stdout: Pipe, stderr: Pipe, authFile: URL) {
    self.authURL = authURL
    self.loginId = loginId
    self.process = process
    self.stdin = stdin
    self.stdout = stdout
    self.stderr = stderr
    self.authFile = authFile
  }

  deinit {
    stateQueue.sync {
      cleanupLocked()
    }
  }

  public func waitForCompletion() async throws {
    try await withCheckedThrowingContinuation { continuation in
      stateQueue.async {
        if let completion = self.completion {
          continuation.resume(with: completion)
        } else if self.continuation == nil {
          self.continuation = continuation
        } else {
          continuation.resume(throwing: CodexAppServerClientError.loginFailed("Login is already being awaited."))
        }
      }
    }
  }

  public func cancel() {
    stateQueue.async {
      guard self.completion == nil else {
        return
      }

      self.writeJSON([
        "jsonrpc": "2.0",
        "id": 3,
        "method": "account/login/cancel",
        "params": ["loginId": self.loginId]
      ])
      self.finishLocked(.failure(CodexAppServerClientError.loginFailed("Login was cancelled.")))
    }
  }

  fileprivate func finish(with result: Result<Void, Error>) {
    stateQueue.async {
      self.finishLocked(result)
    }
  }

  private func finishLocked(_ result: Result<Void, Error>) {
    guard completion == nil else {
      return
    }

    let finalResult: Result<Void, Error>
    if case .success = result, !FileManager.default.fileExists(atPath: authFile.path) {
      finalResult = .failure(CodexAppServerClientError.invalidResponse("login completed but auth.json was not written."))
    } else {
      finalResult = result
    }

    completion = finalResult
    continuation?.resume(with: finalResult)
    continuation = nil
    cleanupLocked()
  }

  private func writeJSON(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else {
      return
    }

    stdin.fileHandleForWriting.write(data + Data("\n".utf8))
  }

  private func cleanupLocked() {
    guard !isCleanedUp else {
      return
    }

    isCleanedUp = true
    stdout.fileHandleForReading.readabilityHandler = nil
    stderr.fileHandleForReading.readabilityHandler = nil
    try? stdin.fileHandleForWriting.close()
    if process.isRunning {
      process.terminate()
    }
    process.waitUntilExit()
  }
}

public struct CodexAppServerClient: Sendable {
  private let parser: RateLimitParser
  private let timeout: TimeInterval

  public init(parser: RateLimitParser = RateLimitParser(), timeout: TimeInterval = 15) {
    self.parser = parser
    self.timeout = timeout
  }

  public func readUsage(authFile: URL) async throws -> UsageValues {
    try await Task.detached(priority: .utility) {
      try readUsageSynchronously(authFile: authFile, parser: parser, timeout: timeout)
    }.value
  }

  public func startChatGPTLogin(authFolder: URL) async throws -> CodexChatGPTLoginSession {
    try await Task.detached(priority: .userInitiated) {
      try startChatGPTLoginSynchronously(authFolder: authFolder, timeout: timeout)
    }.value
  }
}

private func startChatGPTLoginSynchronously(authFolder: URL, timeout: TimeInterval) throws -> CodexChatGPTLoginSession {
  let fileManager = FileManager.default
  try fileManager.createDirectory(at: authFolder, withIntermediateDirectories: true)
  try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: authFolder.path)

  let process = Process()
  process.executableURL = try resolveCodexExecutable()
  process.arguments = ["app-server", "--listen", "stdio://"]
  var environment = ProcessInfo.processInfo.environment
  environment["CODEX_HOME"] = authFolder.path
  environment["PATH"] = codexSearchPaths().joined(separator: ":")
  process.environment = environment

  let stdin = Pipe()
  let stdout = Pipe()
  let stderr = Pipe()
  process.standardInput = stdin
  process.standardOutput = stdout
  process.standardError = stderr

  let outputQueue = DispatchQueue(label: "CodexAppServerClient.login.output")
  var stdoutData = Data()
  var stderrData = Data()
  var initializeResponseData: Data?
  var loginStartResponseData: Data?
  var loginSession: CodexChatGPTLoginSession?
  let initializeSemaphore = DispatchSemaphore(value: 0)
  let loginStartSemaphore = DispatchSemaphore(value: 0)

  process.terminationHandler = { _ in
    initializeSemaphore.signal()
    loginStartSemaphore.signal()
    outputQueue.async {
      let message = processOutputMessage(
        stdoutData: stdoutData,
        stderrData: stderrData,
        fallback: "codex app-server exited before login completed."
      )
      loginSession?.finish(with: .failure(CodexAppServerClientError.invalidResponse(message)))
    }
  }

  stdout.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else {
      return
    }

    outputQueue.sync {
      stdoutData.append(data)
      for lineData in jsonLines(from: stdoutData) {
        guard let response = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
          continue
        }

        if let id = response["id"] as? NSNumber {
          switch id.intValue {
          case 1:
            initializeResponseData = lineData
            initializeSemaphore.signal()
          case 2:
            loginStartResponseData = lineData
            loginStartSemaphore.signal()
          default:
            continue
          }
        } else if let method = response["method"] as? String,
                  method == "account/login/completed",
                  let params = response["params"] as? [String: Any] {
          let completedLoginId = params["loginId"] as? String
          guard completedLoginId == nil || completedLoginId == loginSession?.loginId else {
            continue
          }

          if params["success"] as? Bool == true {
            loginSession?.finish(with: .success(()))
          } else {
            let message = (params["error"] as? String) ?? "The ChatGPT OAuth flow did not complete."
            loginSession?.finish(with: .failure(CodexAppServerClientError.loginFailed(message)))
          }
        }
      }
    }
  }

  stderr.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else {
      return
    }

    outputQueue.sync {
      stderrData.append(data)
    }
  }

  do {
    try process.run()
  } catch {
    throw CodexAppServerClientError.launchFailed(error.localizedDescription)
  }

  let initializeRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex_multiusage","title":"Codex Multiusage","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"# + "\n"
  stdin.fileHandleForWriting.write(Data(initializeRequest.utf8))

  let initializeDeadline = DispatchTime.now() + timeout
  guard initializeSemaphore.wait(timeout: initializeDeadline) == .success else {
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.timedOut
  }

  if outputQueue.sync(execute: { initializeResponseData == nil }) {
    let message = outputQueue.sync {
      processOutputMessage(
        stdoutData: stdoutData,
        stderrData: stderrData,
        fallback: "codex app-server exited before responding to initialize."
      )
    }
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.invalidResponse(message)
  }

  let followupRequest = [
    #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#,
    #"{"jsonrpc":"2.0","id":2,"method":"account/login/start","params":{"type":"chatgpt"}}"#
  ].joined(separator: "\n") + "\n"
  stdin.fileHandleForWriting.write(Data(followupRequest.utf8))

  let loginStartDeadline = DispatchTime.now() + timeout
  guard loginStartSemaphore.wait(timeout: loginStartDeadline) == .success else {
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.timedOut
  }

  let finalInitializeResponse = outputQueue.sync { initializeResponseData }
  let finalLoginStartResponse = outputQueue.sync { loginStartResponseData }

  if let finalInitializeResponse,
     let response = try? JSONSerialization.jsonObject(with: finalInitializeResponse) as? [String: Any],
     let error = response["error"] as? [String: Any] {
    let message = (error["message"] as? String) ?? String(describing: error)
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.invalidResponse(message)
  }

  guard let finalLoginStartResponse,
        let response = try? JSONSerialization.jsonObject(with: finalLoginStartResponse) as? [String: Any] else {
    let message = outputQueue.sync {
      processOutputMessage(
        stdoutData: stdoutData,
        stderrData: stderrData,
        fallback: "codex app-server exited before returning ChatGPT login details."
      )
    }
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.invalidResponse(message)
  }

  if let error = response["error"] as? [String: Any] {
    let message = (error["message"] as? String) ?? String(describing: error)
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.invalidResponse(message)
  }

  guard let result = response["result"] as? [String: Any],
        result["type"] as? String == "chatgpt",
        let loginId = result["loginId"] as? String,
        let authURLString = result["authUrl"] as? String,
        let authURL = URL(string: authURLString) else {
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.invalidResponse("codex app-server did not return a ChatGPT authUrl.")
  }

  let session = CodexChatGPTLoginSession(
    authURL: authURL,
    loginId: loginId,
    process: process,
    stdin: stdin,
    stdout: stdout,
    stderr: stderr,
    authFile: authFolder.appendingPathComponent("auth.json", isDirectory: false)
  )
  outputQueue.sync {
    loginSession = session
  }
  return session
}

private func readUsageSynchronously(authFile: URL, parser: RateLimitParser, timeout: TimeInterval) throws -> UsageValues {
  let fileManager = FileManager.default
  guard fileManager.fileExists(atPath: authFile.path) else {
    throw CodexAppServerClientError.authFileMissing(authFile)
  }

  let codexHome = fileManager.temporaryDirectory
    .appendingPathComponent("codex-multiusage-\(UUID().uuidString)", isDirectory: true)
  let isolatedAuth = codexHome.appendingPathComponent("auth.json")

  try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
  defer { try? fileManager.removeItem(at: codexHome) }

  try fileManager.copyItem(at: authFile, to: isolatedAuth)
  try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexHome.path)
  try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: isolatedAuth.path)

  let process = Process()
  process.executableURL = try resolveCodexExecutable()
  process.arguments = ["app-server", "--listen", "stdio://"]
  var environment = ProcessInfo.processInfo.environment
  environment["CODEX_HOME"] = codexHome.path
  environment["PATH"] = codexSearchPaths().joined(separator: ":")
  process.environment = environment

  let stdin = Pipe()
  let stdout = Pipe()
  let stderr = Pipe()
  process.standardInput = stdin
  process.standardOutput = stdout
  process.standardError = stderr

  let outputQueue = DispatchQueue(label: "CodexAppServerClient.output")
  var stdoutData = Data()
  var stderrData = Data()
  var initializeResponseData: Data?
  var rateLimitResponseData: Data?
  let initializeSemaphore = DispatchSemaphore(value: 0)
  let responseSemaphore = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in
    initializeSemaphore.signal()
    responseSemaphore.signal()
  }

  stdout.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else {
      return
    }

    outputQueue.sync {
      stdoutData.append(data)
      for lineData in jsonLines(from: stdoutData) {
        guard let response = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let id = response["id"] as? NSNumber else {
          continue
        }

        switch id.intValue {
        case 1:
          initializeResponseData = lineData
          initializeSemaphore.signal()
        case 2:
          rateLimitResponseData = lineData
          responseSemaphore.signal()
        default:
          continue
        }
      }
    }
  }

  stderr.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else {
      return
    }

    outputQueue.sync {
      stderrData.append(data)
    }
  }

  do {
    try process.run()
  } catch {
    throw CodexAppServerClientError.launchFailed(error.localizedDescription)
  }

  let initializeRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex_multiusage","title":"Codex Multiusage","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"# + "\n"
  stdin.fileHandleForWriting.write(Data(initializeRequest.utf8))

  let initializeDeadline = DispatchTime.now() + timeout
  guard initializeSemaphore.wait(timeout: initializeDeadline) == .success else {
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.timedOut
  }

  if outputQueue.sync(execute: { initializeResponseData == nil }) {
    let message = outputQueue.sync {
      processOutputMessage(
        stdoutData: stdoutData,
        stderrData: stderrData,
        fallback: "codex app-server exited before responding to initialize."
      )
    }
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.invalidResponse(message)
  }

  let followupRequest = [
    #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#,
    #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":null}"#
  ].joined(separator: "\n") + "\n"
  stdin.fileHandleForWriting.write(Data(followupRequest.utf8))

  let deadline = DispatchTime.now() + timeout
  guard responseSemaphore.wait(timeout: deadline) == .success else {
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.timedOut
  }

  if outputQueue.sync(execute: { rateLimitResponseData == nil }) {
    let message = outputQueue.sync {
      processOutputMessage(
        stdoutData: stdoutData,
        stderrData: stderrData,
        fallback: "codex app-server exited before returning rate limits."
      )
    }
    cleanup(process: process, stdout: stdout, stderr: stderr)
    throw CodexAppServerClientError.invalidResponse(message)
  }

  try? stdin.fileHandleForWriting.close()
  cleanup(process: process, stdout: stdout, stderr: stderr)

  let finalOutput = outputQueue.sync { stdoutData }
  let finalError = outputQueue.sync { stderrData }
  let finalInitializeResponse = outputQueue.sync { initializeResponseData }
  let finalRateLimitResponse = outputQueue.sync { rateLimitResponseData }

  if let finalInitializeResponse,
     let response = try? JSONSerialization.jsonObject(with: finalInitializeResponse) as? [String: Any],
     let error = response["error"] as? [String: Any] {
    let message = (error["message"] as? String) ?? String(describing: error)
    throw CodexAppServerClientError.invalidResponse(message)
  }

  guard let finalRateLimitResponse else {
    let stderrText = String(data: finalError, encoding: .utf8) ?? ""
    if finalOutput.isEmpty, stderrText.isEmpty {
      throw CodexAppServerClientError.emptyResponse
    }
    let stdoutText = String(data: finalOutput, encoding: .utf8) ?? ""
    let message = [stdoutText, stderrText]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    throw CodexAppServerClientError.invalidResponse(message)
  }

  if let response = try? JSONSerialization.jsonObject(with: finalRateLimitResponse) as? [String: Any],
     let error = response["error"] as? [String: Any] {
    let message = (error["message"] as? String) ?? String(describing: error)
    throw CodexAppServerClientError.invalidResponse(message)
  }

  return try parser.parse(finalRateLimitResponse)
}

private func resolveCodexExecutable() throws -> URL {
  let fileManager = FileManager.default

  if let explicitPath = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"],
     fileManager.isExecutableFile(atPath: explicitPath) {
    return URL(fileURLWithPath: explicitPath)
  }

  for directory in codexSearchPaths() {
    let candidate = URL(fileURLWithPath: directory).appendingPathComponent("codex").path
    if fileManager.isExecutableFile(atPath: candidate) {
      return URL(fileURLWithPath: candidate)
    }
  }

  throw CodexAppServerClientError.launchFailed(
    "Could not find the codex CLI. Install Codex CLI or set CODEX_CLI_PATH to its full path."
  )
}

private func codexSearchPaths() -> [String] {
  let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  let packagedAppFallbacks = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "\(home)/.local/bin",
    "\(home)/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin"
  ]

  return (environmentPath.split(separator: ":").map(String.init) + packagedAppFallbacks)
    .filter { !$0.isEmpty }
    .reduce(into: []) { uniquePaths, path in
      if !uniquePaths.contains(path) {
        uniquePaths.append(path)
      }
    }
}

private func cleanup(process: Process, stdout: Pipe, stderr: Pipe) {
  if process.isRunning {
    process.terminate()
  }
  process.waitUntilExit()
  stdout.fileHandleForReading.readabilityHandler = nil
  stderr.fileHandleForReading.readabilityHandler = nil
}

private func processOutputMessage(stdoutData: Data, stderrData: Data, fallback: String) -> String {
  let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
  let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
  let message = [stdoutText, stderrText]
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    .joined(separator: "\n")
  return message.isEmpty ? fallback : message
}

private func jsonLines(from data: Data) -> [Data] {
  let text = String(data: data, encoding: .utf8) ?? ""
  return text.split(separator: "\n").compactMap { line in
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
      return nil
    }

    let lineData = Data(trimmed.utf8)
    if (try? JSONSerialization.jsonObject(with: lineData)) != nil {
      return lineData
    }

    return nil
  }
}
