import AgentProtocol
import BrowserEngine
import BrowserEvents
import BrowserVerification
import EngineCore
import EngineRuntime
import Foundation
import Testing

@Test @MainActor func taskVerificationDistinguishesVerifiedFailedAndInconclusive() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "verification")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id,
    html: """
      <html><head><title>Deployment ready</title></head>
      <body><button id="deploy" aria-label="Deploy">Deploy</button></body></html>
      """,
    url: URL(string: "https://example.test/build?token=private")!)

  let validPlan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "url", assertion: .pageURL(.init("https://example.test/build", mode: .prefix))),
      BrowserVerificationCheck(
        id: "title", assertion: .pageTitle(.init("Deployment ready"))),
      BrowserVerificationCheck(
        id: "deploy", assertion: .element(selector: "#deploy", condition: .visible)),
    ])
  let verified = try await engine.verify(validPlan)
  #expect(verified.status == .verified)
  #expect(verified.evidence.allSatisfy { $0.status == .verified })
  #expect(!verified.evidence.map(\.summary).joined().contains("private"))

  let invalidPlan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "wrong-title", assertion: .pageTitle(.init("Deployment failed"))),
      BrowserVerificationCheck(
        id: "missing", assertion: .element(selector: "#missing", condition: .exists)),
    ])
  let failed = try await engine.verify(invalidPlan)
  #expect(failed.status == .failed)
  #expect(failed.evidence.filter { $0.status == .failed }.count == 2)

  let unobservableNetwork = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "subresource", assertion: .navigationResponse(
          url: .init("https://api.example.test/deploy"), statusCode: 200,
          sinceSequence: 0))
    ])
  let inconclusive = try await engine.verify(unobservableNetwork)
  #expect(inconclusive.status == .inconclusive)

  let cursor = await engine.runtime.events.lastSequence
  await engine.runtime.events.publish(
    .networkNavigationResponse(
      url: "https://api.example.test/deploy?token=private", statusCode: 200,
      mimeType: "application/json"),
    identity: BrowserEventIdentity(context: context.id, page: page.id))
  let postActionPlan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "response", assertion: .navigationResponse(
          url: .init("https://api.example.test/deploy", mode: .prefix),
          statusCode: 200, sinceSequence: cursor))
    ])
  #expect(try await engine.verify(postActionPlan).status == .verified)
  let afterResponse = await engine.runtime.events.lastSequence
  let staleOnlyPlan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "stale-response", assertion: .navigationResponse(
          url: .init("https://api.example.test/deploy", mode: .prefix),
          statusCode: 200, sinceSequence: afterResponse))
    ])
  #expect(try await engine.verify(staleOnlyPlan).status == .inconclusive)
}

@Test @MainActor func dispatcherExposesVerificationAndScopedEvents() async throws {
  let engine = NativeBrowserEngine()
  let dispatcher = AgentCommandDispatcher(engine: engine)
  let context = await engine.runtime.createContext(name: "protocol-verification")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id, html: "<html><head><title>Ready</title></head><body>ok</body></html>",
    url: URL(string: "https://example.test/ready")!)

  let plan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(id: "ready", assertion: .pageTitle(.init("Ready")))
    ])
  let verificationInput = TaskVerify.Input(plan: plan)
  let verificationResponse = await dispatcher.handle(
    AgentRequest(
      method: .taskVerify, params: try AgentProcedureCodec.encodeParams(verificationInput)))
  #expect(verificationResponse.error == nil)
  let verification = try AgentProcedureCodec.decodeOutput(
    BrowserVerificationResult.self, from: #require(verificationResponse.result))
  #expect(verification.status == .verified)
  #expect(verification.pageID == page.id)
  #expect(verification.contextID == context.id)

  await engine.runtime.events.publish(
    .executionStarted(id: "event-test"),
    identity: BrowserEventIdentity(context: context.id, page: page.id, branch: "branch-test"))
  let eventsResponse = await dispatcher.handle(
    AgentRequest(
      method: .eventsRecent,
      params: ["context": .uint(context.id.rawValue), "limit": .integer(10)]))
  #expect(eventsResponse.error == nil)
  let eventOutput = try AgentProcedureCodec.decodeOutput(
    EventsRecent.Output.self, from: #require(eventsResponse.result))
  let emitted = try #require(eventOutput.events.last { $0.name == "execution.started" })
  #expect(emitted.context == context.id.rawValue)
  #expect(emitted.page == page.id.rawValue)
  #expect(emitted.branch == "branch-test")
  #expect(eventOutput.nextSequence >= emitted.sequence)
}

@Test @MainActor func dispatcherBlocksVerificationAndEventReadsDuringHumanHandoff() async throws {
  let engine = NativeBrowserEngine()
  let dispatcher = AgentCommandDispatcher(engine: engine)
  let context = await engine.runtime.createContext(name: "verification-handoff")
  let profileDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try await engine.runtime.openProfile(contextID: context.id, directory: profileDirectory)
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.requestHandoff(
    pageID: page.id, category: .mfa, reason: "Complete the sign-in challenge", agent: "worker-1")

  let plan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [BrowserVerificationCheck(id: "title", assertion: .pageTitle(.init("Signed in")))])
  let response = await dispatcher.handle(
    AgentRequest(
      method: .taskVerify,
      params: try AgentProcedureCodec.encodeParams(TaskVerify.Input(plan: plan))))

  #expect(response.error?.code == "handoff_active")

  let eventsResponse = await dispatcher.handle(
    AgentRequest(
      method: .eventsRecent,
      params: ["context": .uint(context.id.rawValue), "limit": .integer(10)]))
  #expect(eventsResponse.error?.code == "handoff_active")

  try await engine.runtime.closePage(page.id)
  try await engine.runtime.destroyContext(context.id)
  try FileManager.default.removeItem(at: profileDirectory)
}

@Test @MainActor func externalVerifierCanSupplyIndependentEvidence() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "external-verifier")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id, html: "<html><body>Ready</body></html>",
    url: URL(string: "https://example.test")!)
  let plan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "live-endpoint", assertion: .external(
          identifier: "endpoint", payload: Data("https://deploy.example.test/health".utf8)))
    ])
  let withoutProvider = try await engine.verify(plan)
  #expect(withoutProvider.status == .inconclusive)

  let withProvider = try await engine.verify(
    plan, using: [EndpointVerifier()])
  #expect(withProvider.status == .verified)
  #expect(withProvider.evidence.first?.source == "external.endpoint")
}

@Test @MainActor func downloadVerificationChecksNewWebKitArtifactOnDisk() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "download-verification")
  let page = try await engine.runtime.createPage(contextID: context.id)
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let artifact = directory.appendingPathComponent("artifact.zip")
  try Data("archive".utf8).write(to: artifact)
  let cursor = await engine.runtime.events.lastSequence
  await engine.runtime.events.publish(
    .downloadFinished(url: "https://example.test/artifact.zip?token=private", path: artifact.path),
    identity: BrowserEventIdentity(context: context.id, page: page.id))
  let plan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(
        id: "artifact", assertion: .download(
          url: .init("https://example.test/artifact.zip", mode: .prefix),
          minimumBytes: 7, verifyFileExists: true, downloadID: nil,
          sinceSequence: cursor))
    ])
  let verified = try await engine.verify(plan)
  #expect(verified.status == .verified)

  try FileManager.default.removeItem(at: artifact)
  #expect(try await engine.verify(plan).status == .failed)
}

private struct EndpointVerifier: BrowserExternalVerifier {
  let identifier = "endpoint"

  func verify(payload: Data) async throws -> BrowserExternalVerification {
    guard String(decoding: payload, as: UTF8.self).hasPrefix("https://") else {
      return BrowserExternalVerification(status: .failed, summary: "Endpoint input was invalid.")
    }
    return BrowserExternalVerification(status: .verified, summary: "Live endpoint returned healthy.")
  }
}
