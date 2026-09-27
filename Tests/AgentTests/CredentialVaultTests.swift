import AgentProtocol
import BrowserEngine
import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

// Agent-readable credential vault: unit, dispatcher, and live-WebKit flow
// tests against the deterministic local fixture app (Fixtures/credvault).
private func credentialEngine(secrets: EphemeralCredentialSecrets = EphemeralCredentialSecrets())
  -> (NativeBrowserEngine, EphemeralCredentialSecrets)
{
  let runtime = BrowserRuntime(credentialSecrets: secrets)
  return (NativeBrowserEngine(runtime: runtime), secrets)
}

private func temporaryProfileDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

struct CredentialVaultUnitTests {
  @Test func saveListGetUpdateDelete() async throws {
    let (engine, _) = credentialEngine()
    let context = await engine.runtime.createContext(name: "vault-unit")
    try await engine.runtime.openProfile(
      contextID: context.id, directory: temporaryProfileDirectory())

    let saved = try await engine.runtime.saveCredential(
      contextID: context.id, origin: "https://example.com", username: "user@example.com",
      password: "s3cr3t-1", label: "Personal")
    #expect(!saved.id.isEmpty)
    #expect(saved.origin == "https://example.com")
    #expect(saved.label == "Personal")

    let listed = try await engine.runtime.listCredentials(contextID: context.id)
    #expect(listed.count == 1)
    #expect(listed[0].id == saved.id)
    // Metadata carries no secret: encoded form must not contain it.
    let encoded = String(data: try JSONEncoder().encode(listed), encoding: .utf8) ?? ""
    #expect(!encoded.contains("s3cr3t-1"))

    let secret = try await engine.runtime.credentialSecret(
      contextID: context.id, credentialID: saved.id)
    #expect(secret.username == "user@example.com")
    #expect(secret.password == "s3cr3t-1")

    let updated = try await engine.runtime.saveCredential(
      contextID: context.id, origin: "https://example.com/", username: "user@example.com",
      password: "s3cr3t-2")
    #expect(updated.id == saved.id, "upsert on (origin, username) keeps the credential id")
    #expect(updated.updatedAt >= saved.updatedAt)
    #expect(updated.label == "Personal", "empty label update preserves the existing label")
    let rotated = try await engine.runtime.credentialSecret(
      contextID: context.id, credentialID: saved.id)
    #expect(rotated.password == "s3cr3t-2")

    #expect(try await engine.runtime.deleteCredential(contextID: context.id, credentialID: saved.id))
    #expect(try await engine.runtime.listCredentials(contextID: context.id).isEmpty)
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.credentialSecret(contextID: context.id, credentialID: saved.id)
    }
    try await engine.runtime.destroyContext(context.id)
  }

  @Test func profilesStayIsolated() async throws {
    let (engine, _) = credentialEngine()
    let first = await engine.runtime.createContext(name: "profile-a")
    let second = await engine.runtime.createContext(name: "profile-b")
    try await engine.runtime.openProfile(
      contextID: first.id, directory: temporaryProfileDirectory())
    try await engine.runtime.openProfile(
      contextID: second.id, directory: temporaryProfileDirectory())
    let saved = try await engine.runtime.saveCredential(
      contextID: first.id, origin: "https://example.com", username: "a@example.com",
      password: "profile-a-secret")
    #expect(try await engine.runtime.listCredentials(contextID: second.id).isEmpty)
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.credentialSecret(contextID: second.id, credentialID: saved.id)
    }
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.deleteCredential(contextID: second.id, credentialID: saved.id)
    }
    try await engine.runtime.destroyContext(first.id)
    try await engine.runtime.destroyContext(second.id)
  }

  @Test func validationRejectsMalformedInput() async throws {
    let (engine, _) = credentialEngine()
    let context = await engine.runtime.createContext(name: "vault-validation")
    try await engine.runtime.openProfile(
      contextID: context.id, directory: temporaryProfileDirectory())
    // Not a URL at all.
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.saveCredential(
        contextID: context.id, origin: "not a url", username: "u", password: "p")
    }
    // Remote http is refused (would leak over cleartext).
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.saveCredential(
        contextID: context.id, origin: "http://example.com", username: "u", password: "p")
    }
    // Loopback http is allowed for local test apps and intranet services.
    for origin in ["http://localhost:18771", "http://127.0.0.1:18771", "http://[::1]:18771"] {
      let record = try await engine.runtime.saveCredential(
        contextID: context.id, origin: origin, username: "local", password: "p")
      #expect(record.origin == origin)
      #expect(try await engine.runtime.deleteCredential(contextID: context.id, credentialID: record.id))
    }
    // Empty or blank credentials never become records (no silent harvesting).
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.saveCredential(
        contextID: context.id, origin: "https://example.com", username: "   ", password: "p")
    }
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.saveCredential(
        contextID: context.id, origin: "https://example.com", username: "u", password: "")
    }
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.saveCredential(
        contextID: context.id, origin: "https://example.com", username: "u", password: "p",
        label: String(repeating: "x", count: 129))
    }
    #expect(try await engine.runtime.listCredentials(contextID: context.id).isEmpty)
    // Unknown ids fail closed.
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.credentialSecret(contextID: context.id, credentialID: "nope")
    }
    await #expect(throws: CredentialVaultError.self) {
      try await engine.runtime.deleteCredential(contextID: context.id, credentialID: "nope")
    }
    try await engine.runtime.destroyContext(context.id)
  }

  @Test func multipleAccountsShareOneOrigin() async throws {
    let (engine, _) = credentialEngine()
    let context = await engine.runtime.createContext(name: "vault-multi")
    try await engine.runtime.openProfile(
      contextID: context.id, directory: temporaryProfileDirectory())
    try await engine.runtime.saveCredential(
      contextID: context.id, origin: "https://example.com", username: "one@example.com",
      password: "pw-1", label: "Work")
    try await engine.runtime.saveCredential(
      contextID: context.id, origin: "https://example.com", username: "two@example.com",
      password: "pw-2", label: "Personal")
    let listed = try await engine.runtime.listCredentials(
      contextID: context.id, origin: "https://example.com")
    #expect(listed.count == 2)
    #expect(Set(listed.map(\.id)).count == 2)
    #expect(listed.map(\.username).sorted() == ["one@example.com", "two@example.com"])
    try await engine.runtime.destroyContext(context.id)
  }

  @Test func secretsNeverLeakIntoUnrelatedOutputs() async throws {
    let canary = "canary-\(UUID().uuidString)"
    let (engine, _) = credentialEngine()
    let context = await engine.runtime.createContext(name: "vault-noleak")
    try await engine.runtime.openProfile(
      contextID: context.id, directory: temporaryProfileDirectory())
    let saved = try await engine.runtime.saveCredential(
      contextID: context.id, origin: "https://example.com", username: "u", password: canary)
    let dispatcher = AgentCommandDispatcher(engine: engine)
    func encoded(_ response: AgentResponse) throws -> String {
      guard let result = response.result else { return "" }
      return String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? ""
    }
    // list must not carry the secret…
    let listed = await dispatcher.handle(
      AgentRequest(method: "credentials.list", params: ["context": .number(Double(context.id.rawValue))]))
    #expect(!(try encoded(listed)).contains(canary))
    // …but explicit get returns it (that is the documented retrieval path).
    let gotten = await dispatcher.handle(
      AgentRequest(
        method: "credentials.get",
        params: [
          "context": .number(Double(context.id.rawValue)), "credential": .string(saved.id),
        ]))
    #expect((try encoded(gotten)).contains(canary))
    // Nothing else repeats it: errors, snapshots of other surfaces, fleet.
    let failures = [
      await dispatcher.handle(
        AgentRequest(method: "credentials.get", params: ["context": .number(Double(context.id.rawValue)), "credential": .string("missing")])),
      await dispatcher.handle(
        AgentRequest(method: "credentials.delete", params: ["context": .number(Double(context.id.rawValue)), "credential": .string("missing")])),
      await dispatcher.handle(
        AgentRequest(method: "page.list", params: ["context": .number(9_999_999)])),
      await dispatcher.handle(AgentRequest(method: "no.such.method")),
      await dispatcher.handle(AgentRequest(method: "context.list")),
      await dispatcher.handle(AgentRequest(method: "fleet.stats")),
      await dispatcher.handle(AgentRequest(method: "fleet.pages")),
    ]
    for response in failures {
      if let message = response.error?.message { #expect(!message.contains(canary)) }
      #expect(!(try encoded(response)).contains(canary))
    }
    try await engine.runtime.destroyContext(context.id)
  }
}

struct CredentialLoginFlowTests {
  private func fixtureDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/credvault", isDirectory: true)
  }

  private func shell(_ path: String, _ arguments: [String]) -> (code: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do { try process.run() } catch { return (-1, "") }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }

  private func startFixtureServer(port: UInt16) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [
      "-m", "http.server", "\(port)", "--bind", "127.0.0.1",
      "--directory", fixtureDirectory().path,
    ]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if !process.isRunning { throw BrowserRuntimeError.timeout("fixture server exited early") }
      let probe = shell(
        "/usr/bin/curl",
        ["-s", "-o", "/dev/null", "-w", "%{http_code}", "http://127.0.0.1:\(port)/signup.html"])
      if probe.code == 0, probe.output == "200" { return process }
      Thread.sleep(forTimeInterval: 0.2)
    }
    process.terminate()
    throw BrowserRuntimeError.timeout("fixture server never became reachable")
  }

  private func pageText(
    _ runtime: BrowserRuntime, pageID: PageID, containing marker: String,
    deadlineSeconds: Double = 25
  ) async throws -> String {
    let deadline = Date().addingTimeInterval(deadlineSeconds)
    var text = ""
    while Date() < deadline {
      text = (try? await runtime.webDocumentText(pageID: pageID)) ?? ""
      if text.contains(marker) { return text }
      try await Task.sleep(for: .milliseconds(250))
    }
    return text
  }

  private func inputValue(
    _ runtime: BrowserRuntime, pageID: PageID, id: String,
    deadlineSeconds: Double = 15
  ) async throws -> String {
    let deadline = Date().addingTimeInterval(deadlineSeconds)
    var value = ""
    while Date() < deadline {
      let result = try? await runtime.evaluate(
        pageID: pageID, source: "document.getElementById('\(id)')?.value ?? ''")
      value = result?.value ?? ""
      if !value.isEmpty { return value }
      try await Task.sleep(for: .milliseconds(250))
    }
    return value
  }

  @Test @MainActor func completeSignupSaveReloginFlow() async throws {
    let server = try startFixtureServer(port: 18771)
    defer { server.terminate() }
    let base = "http://127.0.0.1:18771"
    let secrets = EphemeralCredentialSecrets()
    let engine = NativeBrowserEngine(runtime: BrowserRuntime(credentialSecrets: secrets))
    let profileDir = try temporaryProfileDirectory()
    let context = await engine.runtime.createContext(name: "cred-flow")
    try await engine.runtime.openProfile(contextID: context.id, directory: profileDir)

    let email = "agent-\(UUID().uuidString)@example.com"
    let password = "flow-secret-1"

    // 1–2. Open the test site, create the account through the real page.
    let signup = try await engine.runtime.createPage(contextID: context.id)
    try await engine.runtime.navigate(
      pageID: signup.id, to: URL(string: "\(base)/signup.html")!, settle: .complete)
    _ = try await engine.runtime.evaluate(
      pageID: signup.id,
      source:
        "document.getElementById('email').value = \(jsonLiteral(email)); document.getElementById('new-password').value = \(jsonLiteral(password)); document.getElementById('signup').requestSubmit(); 'submitted'")
    let created = try await pageText(
      engine.runtime, pageID: signup.id, containing: "Account created for")
    #expect(created.contains(email), "signup page must report account creation")

    // 3–5. Explicit save through Aether's credential API; metadata persists,
    // secret goes to the secret store, SQLite holds metadata only.
    let saved = try await engine.runtime.saveCredential(
      contextID: context.id, origin: base, username: email, password: password,
      label: "Fixture")
    #expect(saved.origin == base)
    let listed = try await engine.runtime.listCredentials(contextID: context.id, origin: base)
    #expect(listed.count == 1 && listed[0].id == saved.id)
    let secret = try await engine.runtime.credentialSecret(
      contextID: context.id, credentialID: saved.id)
    #expect(secret.password == password)

    // 6–9. Fresh page, same profile: retrieve through the agent API, fill the
    // generic login form, submit, and verify the site authenticates us.
    let login = try await engine.runtime.createPage(contextID: context.id)
    try await engine.runtime.navigate(
      pageID: login.id, to: URL(string: "\(base)/login.html")!, settle: .complete)
    let candidates = try await engine.runtime.listCredentials(
      contextID: context.id, origin: base)
    #expect(candidates.count == 1)
    try await engine.runtime.fillCredential(pageID: login.id, credentialID: candidates[0].id)
    #expect(try await inputValue(engine.runtime, pageID: login.id, id: "email") == email)
    #expect(try await inputValue(engine.runtime, pageID: login.id, id: "password") == password)
    _ = try await engine.runtime.evaluate(
      pageID: login.id, source: "document.getElementById('login').requestSubmit(); 'submitted'")
    let signedIn = try await pageText(
      engine.runtime, pageID: login.id, containing: "Signed in as")
    #expect(signedIn.contains(email), "site must report successful authentication")

    // Wrong profile cannot see or use the credential.
    let stranger = await engine.runtime.createContext(name: "cred-stranger")
    try await engine.runtime.openProfile(
      contextID: stranger.id, directory: temporaryProfileDirectory())
    #expect(try await engine.runtime.listCredentials(contextID: stranger.id).isEmpty)

    // Restart persistence: same profile directory, same secret store.
    try await engine.runtime.destroyContext(context.id)
    try await engine.runtime.destroyContext(stranger.id)
    let relaunched = NativeBrowserEngine(runtime: BrowserRuntime(credentialSecrets: secrets))
    let revived = await relaunched.runtime.createContext(name: "cred-revived")
    try await relaunched.runtime.openProfile(contextID: revived.id, directory: profileDir)
    let survivors = try await relaunched.runtime.listCredentials(
      contextID: revived.id, origin: base)
    #expect(survivors.count == 1 && survivors[0].username == email)
    let survivingSecret = try await relaunched.runtime.credentialSecret(
      contextID: revived.id, credentialID: survivors[0].id)
    #expect(survivingSecret.password == password)

    // Update then delete through the API.
    let rotated = try await relaunched.runtime.saveCredential(
      contextID: revived.id, origin: base, username: email, password: "flow-secret-2")
    #expect(rotated.id == saved.id)
    #expect(
      try await relaunched.runtime.credentialSecret(
        contextID: revived.id, credentialID: saved.id
      ).password == "flow-secret-2")
    #expect(
      try await relaunched.runtime.deleteCredential(
        contextID: revived.id, credentialID: saved.id))
    #expect(try await relaunched.runtime.listCredentials(contextID: revived.id).isEmpty)
    try await relaunched.runtime.destroyContext(revived.id)
  }

  private func jsonLiteral(_ value: String) -> String {
    String(data: (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
  }
}

struct CredentialDispatcherTests {
  @Test func wireRoundTrip() async throws {
    let (engine, _) = credentialEngine()
    let context = await engine.runtime.createContext(name: "vault-wire")
    try await engine.runtime.openProfile(
      contextID: context.id, directory: temporaryProfileDirectory())
    let dispatcher = AgentCommandDispatcher(engine: engine)
    let saved = await dispatcher.handle(
      AgentRequest(
        method: "credentials.save",
        params: [
          "context": .number(Double(context.id.rawValue)),
          "origin": .string("https://example.com"),
          "username": .string("wire@example.com"),
          "password": .string("wire-secret"),
          "label": .string("Wire"),
        ]))
    #expect(saved.error == nil)
    guard case .object(let fields) = saved.result,
      case .string(let credentialID) = fields["id"]
    else { Issue.record("expected a credential id"); return }
    #expect(fields["password"] == nil, "save response must not echo the secret")
    let deleted = await dispatcher.handle(
      AgentRequest(
        method: "credentials.delete",
        params: [
          "context": .number(Double(context.id.rawValue)),
          "credential": .string(credentialID),
        ]))
    if case .object(let removed) = deleted.result {
      #expect(removed["removed"] == .bool(true))
    } else { Issue.record("expected a removal result") }
    try await engine.runtime.destroyContext(context.id)
  }
}
