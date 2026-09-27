import Foundation
import AgentProtocol
import Darwin
import Testing

@Test func browserctlReturnsFailureForRejectedDaemonRequest() async throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let browserd = repository.appendingPathComponent(".build/debug/browserd")
  let browserctl = repository.appendingPathComponent(".build/debug/browserctl")
  #expect(FileManager.default.isExecutableFile(atPath: browserd.path))
  #expect(FileManager.default.isExecutableFile(atPath: browserctl.path))

  let socket = URL(fileURLWithPath: "/tmp/aectl-\(UUID().uuidString.prefix(8)).sock")
  let daemon = Process()
  daemon.executableURL = browserd
  daemon.arguments = ["--socket", socket.path, "--no-auth"]
  daemon.standardOutput = Pipe()
  daemon.standardError = Pipe()
  try daemon.run()
  defer {
    if daemon.isRunning {
      daemon.terminate()
    }
    try? FileManager.default.removeItem(atPath: socket.path)
    try? FileManager.default.removeItem(atPath: socket.path + ".lock")
  }

  let deadline = Date().addingTimeInterval(5)
  while !FileManager.default.fileExists(atPath: socket.path), Date() < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(FileManager.default.fileExists(atPath: socket.path))

  let command = Process()
  command.executableURL = browserctl
  command.arguments = ["--socket", socket.path, "page-inspect", "999999"]
  let output = Pipe()
  command.standardOutput = output
  command.standardError = Pipe()
  try command.run()
  await waitForExit(command)
  let response = String(
    decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  #expect(command.terminationStatus != 0)
  #expect(response.contains("\"error\""))
  await stopProcess(daemon)
}

@Test func browserctlWorkspaceLeaseCommandsDelegateToDaemon() async throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let browserd = repository.appendingPathComponent(".build/debug/browserd")
  let browserctl = repository.appendingPathComponent(".build/debug/browserctl")
  let suffix = String(UUID().uuidString.prefix(8))
  let socket = URL(fileURLWithPath: "/tmp/aectl-\(suffix).sock")
  let profile = URL(fileURLWithPath: "/tmp/aectl-profile-\(suffix)", isDirectory: true)
  let daemon = Process()
  daemon.executableURL = browserd
  daemon.arguments = ["--socket", socket.path, "--no-auth"]
  daemon.standardOutput = Pipe()
  daemon.standardError = Pipe()
  try daemon.run()
  defer {
    if daemon.isRunning {
      daemon.terminate()
    }
    try? FileManager.default.removeItem(atPath: socket.path)
    try? FileManager.default.removeItem(atPath: socket.path + ".lock")
    try? FileManager.default.removeItem(at: profile)
  }

  let deadline = Date().addingTimeInterval(5)
  while !FileManager.default.fileExists(atPath: socket.path), Date() < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(FileManager.default.fileExists(atPath: socket.path))

  let contextResponse = try await runBrowserctl(browserctl, socket: socket.path, [
    "context-create", "lease-cli-test",
  ])
  let contextID = try #require(contextResponse.result?["id"]?.exactUInt64)
  let opened = try await runBrowserctl(browserctl, socket: socket.path, [
    "context-open-profile", String(contextID), profile.path,
  ])
  #expect(opened.error == nil)

  let branchID = UUID().uuidString
  let acquired = try await runBrowserctl(browserctl, socket: socket.path, [
    "workspace-lease-acquire", String(contextID), "worker-cli", "30", branchID,
    "/tmp/aether-repo", "/tmp/aether-repo/.worktrees/worker-cli",
  ])
  let leaseID = try #require(acquired.result?["leaseID"]?.string)
  #expect(acquired.result?["agentID"]?.string == "worker-cli")
  #expect(acquired.result?["branchID"]?.string == branchID)
  #expect(acquired.result?["repositoryRoot"]?.string == "/tmp/aether-repo")

  let listed = try await runBrowserctl(browserctl, socket: socket.path, [
    "workspace-lease-list", String(contextID),
  ])
  #expect(listed.result?.array?.count == 1)
  #expect(listed.result?.array?.first?["leaseID"]?.string == leaseID)

  let renewed = try await runBrowserctl(browserctl, socket: socket.path, [
    "workspace-lease-renew", String(contextID), leaseID, "worker-cli", "60",
  ])
  #expect(renewed.result?["state"]?.string == "active")

  let released = try await runBrowserctl(browserctl, socket: socket.path, [
    "workspace-lease-release", String(contextID), leaseID, "worker-cli",
  ])
  #expect(released.result?["state"]?.string == "released")

  let reacquired = try await runBrowserctl(browserctl, socket: socket.path, [
    "workspace-lease-acquire", String(contextID), "worker-cli", "30",
  ])
  let nextLeaseID = try #require(reacquired.result?["leaseID"]?.string)
  let cancelled = try await runBrowserctl(browserctl, socket: socket.path, [
    "workspace-lease-cancel", String(contextID), nextLeaseID,
  ])
  #expect(cancelled.result?["state"]?.string == "cancelled")
  await stopProcess(daemon)
}

private func runBrowserctl(
  _ binary: URL, socket: String, _ command: [String]
) async throws -> AgentResponse {
  let process = Process()
  process.executableURL = binary
  process.arguments = ["--socket", socket] + command
  let output = Pipe()
  let errors = Pipe()
  process.standardOutput = output
  process.standardError = errors
  try process.run()
  await waitForExit(process)
  let data = output.fileHandleForReading.readDataToEndOfFile()
  guard process.terminationStatus == 0 else {
    let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    throw BrowserctlIntegrationError.failed(process.terminationStatus, error)
  }
  return try AgentCodec.decodeResponse(data)
}

private func waitForExit(_ process: Process) async {
  await waitForExit(process, timeout: .seconds(15))
}

private func waitForExit(_ process: Process, timeout: Duration) async {
  await withCheckedContinuation { continuation in
    let gate = ProcessExitGate(continuation)
    process.terminationHandler = { _ in gate.complete() }
    guard process.isRunning else {
      gate.complete()
      return
    }
    Task.detached(priority: .utility) {
      try? await Task.sleep(for: timeout)
      guard !gate.isComplete else { return }
      _ = kill(process.processIdentifier, SIGKILL)
      try? await Task.sleep(for: .seconds(2))
      gate.complete()
    }
  }
}

private func stopProcess(_ process: Process) async {
  if process.isRunning {
    process.terminate()
  }
  await waitForExit(process, timeout: .seconds(2))
}

private final class ProcessExitGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  init(_ continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }

  var isComplete: Bool {
    lock.lock()
    defer { lock.unlock() }
    return continuation == nil
  }

  func complete() {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume()
  }
}

private enum BrowserctlIntegrationError: Error {
  case failed(Int32, String)
}
