import BrowserEngine
import EngineCore
import EngineRuntime
import Foundation
import Testing

private func controlContenders() -> (ControlActor, ControlActor, ControlActor) {
  (
    ControlActor(kind: .agent, label: "agent-a"),
    ControlActor(kind: .agent, label: "agent-b"),
    ControlActor(kind: .human, label: "human")
  )
}

private func clickablePage(_ runtime: BrowserRuntime) async throws -> (
  context: BrowserContextInfo, page: BrowserPageInfo, button: InspectedNode
) {
  let context = await runtime.createContext(name: "control")
  let page = try await runtime.createPage(
    contextID: context.id, viewport: Size(width: 200, height: 200))
  _ = try await runtime.loadHTML(
    pageID: page.id,
    html: "<button id='button' style='width:100px;height:50px'>Click</button>",
    url: URL(string: "https://control.test")!)
  _ = try await runtime.evaluate(
    pageID: page.id,
    source:
      "let clicks = 0; document.getElementById('button').addEventListener('click', function() { clicks = clicks + 1; })"
  )
  let button = try #require(try await runtime.query(pageID: page.id, selector: "#button"))
  return (context, page, button)
}

@Test func inputLeaseGivesExclusiveControlToOneContender() async throws {
  let (agentA, agentB, _) = controlContenders()
  let runtime = NativeBrowserEngine().runtime
  let (_, page, button) = try await clickablePage(runtime)
  try await runtime.acquireInput(pageID: page.id, actor: agentA)
  await #expect(throws: PageControlError.inputHeld(agentA)) {
    try await runtime.click(pageID: page.id, actor: agentB, nodeID: button.id)
  }
  await #expect(throws: PageControlError.inputHeld(agentA)) {
    try await runtime.click(pageID: page.id, nodeID: button.id)
  }
  _ = try await runtime.click(pageID: page.id, actor: agentA, nodeID: button.id)
  #expect(try await runtime.evaluate(pageID: page.id, source: "clicks").value == "1")
  try await runtime.handoffInput(pageID: page.id, from: agentA, to: agentB)
  await #expect(throws: PageControlError.inputHeld(agentB)) {
    try await runtime.click(pageID: page.id, actor: agentA, nodeID: button.id)
  }
  _ = try await runtime.click(pageID: page.id, actor: agentB, nodeID: button.id)
  try await runtime.releaseInput(pageID: page.id, actor: agentB)
  _ = try await runtime.click(pageID: page.id, actor: agentA, nodeID: button.id)
  #expect(try await runtime.evaluate(pageID: page.id, source: "clicks").value == "3")
  let events = try await runtime.controlEvents(pageID: page.id)
  let sequences = events.map(\.sequence)
  #expect(sequences == sequences.sorted())
  #expect(Set(sequences).count == sequences.count)
  #expect(events.contains { $0.operation == "acquire" && $0.outcome == "success" })
  #expect(events.contains { $0.operation == "handoff" && $0.outcome == "success" })
  #expect(events.contains { $0.operation == "release" && $0.outcome == "success" })
  #expect(events.contains { $0.outcome == "denied" && $0.error == "input-held" })
  #expect(events.contains { $0.operation == "click" && $0.outcome == "admitted" })
}

@Test func pauseAbortAndResumeAcrossHumanAndAgents() async throws {
  let (agentA, agentB, human) = controlContenders()
  let runtime = NativeBrowserEngine().runtime
  let (_, page, button) = try await clickablePage(runtime)
  try await runtime.acquireInput(pageID: page.id, actor: agentA)
  try await runtime.abortPage(pageID: page.id, actor: human)
  await #expect(throws: PageControlError.paused) {
    try await runtime.click(pageID: page.id, actor: agentA, nodeID: button.id)
  }
  try await runtime.acquireInput(pageID: page.id, actor: agentB)
  await #expect(throws: PageControlError.paused) {
    try await runtime.click(pageID: page.id, actor: agentB, nodeID: button.id)
  }
  await #expect(throws: PageControlError.inputHeld(human)) {
    try await runtime.resumePage(pageID: page.id, actor: agentA)
  }
  try await runtime.resumePage(pageID: page.id, actor: human)
  _ = try await runtime.click(pageID: page.id, actor: agentB, nodeID: button.id)
  #expect(try await runtime.evaluate(pageID: page.id, source: "clicks").value == "1")
  let events = try await runtime.controlEvents(pageID: page.id)
  #expect(events.contains { $0.operation == "abort" && $0.actorLabel == "human" })
  #expect(events.contains { $0.outcome == "denied" && $0.error == "paused" })
}

@Test func navigationApprovalIsOneShot() async throws {
  let (agentA, _, human) = controlContenders()
  let runtime = NativeBrowserEngine().runtime
  let context = await runtime.createContext(name: "approval")
  let page = try await runtime.createPage(contextID: context.id)
  _ = try await runtime.loadHTML(
    pageID: page.id, html: "<p>first</p>", url: URL(string: "https://approval.test/a")!)
  _ = try await runtime.loadHTML(
    pageID: page.id, html: "<p>second</p>", url: URL(string: "https://approval.test/b")!)
  try await runtime.requireNavigationApproval(pageID: page.id, actor: human)
  await #expect(throws: PageControlError.approvalRequired("navigate")) {
    try await runtime.goBack(pageID: page.id, actor: agentA)
  }
  try await runtime.approveNavigation(pageID: page.id, actor: human)
  do {
    _ = try await runtime.goBack(pageID: page.id, actor: agentA)
  } catch is BrowserRuntimeError {
  }
  await #expect(throws: PageControlError.approvalRequired("navigate")) {
    try await runtime.goBack(pageID: page.id, actor: agentA)
  }
  try await runtime.clearNavigationApproval(pageID: page.id, actor: human)
  await #expect(throws: BrowserRuntimeError.self) {
    try await runtime.approveNavigation(pageID: page.id, actor: human)
  }
  let events = try await runtime.controlEvents(pageID: page.id)
  #expect(events.contains { $0.operation == "approval-armed" && $0.outcome == "success" })
  #expect(events.contains { $0.operation == "approval-grant" && $0.outcome == "success" })
  #expect(events.contains { $0.outcome == "denied" && $0.error == "approval-required" })
}

@Test func secretEntryNeverLandsInControlEvents() async throws {
  let (agentA, _, _) = controlContenders()
  let runtime = NativeBrowserEngine().runtime
  let context = await runtime.createContext(name: "secrets")
  let page = try await runtime.createPage(contextID: context.id)
  _ = try await runtime.loadHTML(
    pageID: page.id,
    html: "<input id='pw' type='password'><input id='plain' type='text'>",
    url: URL(string: "https://control.test")!)
  let secret = "s3cr3t-pw-value"
  let password = try #require(try await runtime.query(pageID: page.id, selector: "#pw"))
  let plain = try #require(try await runtime.query(pageID: page.id, selector: "#plain"))
  _ = try await runtime.focus(pageID: page.id, actor: agentA, nodeID: password.id)
  try await runtime.type(pageID: page.id, actor: agentA, nodeID: password.id, text: secret)
  _ = try await runtime.pressKey(pageID: page.id, actor: agentA, key: "!")
  try await runtime.fill(pageID: page.id, actor: agentA, nodeID: plain.id, value: "visible")
  let events = try await runtime.controlEvents(pageID: page.id)
  #expect(!events.isEmpty)
  for event in events {
    #expect(!(event.detail?.contains(secret) ?? false))
  }
  #expect(
    events.contains {
      ($0.operation == "type" || $0.operation == "press") && $0.detail == "redacted"
    })
  #expect(events.contains { $0.operation == "fill" && $0.detail == nil })
}

@Test func controlEventsAreOrderedAcrossThreeContenders() async throws {
  let (agentA, agentB, human) = controlContenders()
  let runtime = NativeBrowserEngine().runtime
  let (_, page, button) = try await clickablePage(runtime)
  _ = try await runtime.click(pageID: page.id, actor: agentA, nodeID: button.id)
  try await runtime.pausePage(pageID: page.id, actor: human)
  await #expect(throws: PageControlError.paused) {
    try await runtime.click(pageID: page.id, actor: agentB, nodeID: button.id)
  }
  try await runtime.resumePage(pageID: page.id, actor: human)
  let events = try await runtime.controlEvents(pageID: page.id)
  let sequences = events.map(\.sequence)
  #expect(sequences == Array(1...UInt64(events.count)))
  let labels = Set(events.map(\.actorLabel))
  #expect(labels.contains("agent-a"))
  #expect(labels.contains("agent-b"))
  #expect(labels.contains("human"))
  let tail = try await runtime.controlEvents(pageID: page.id, after: sequences.first)
  #expect(tail.count == events.count - 1)
  #expect(tail.allSatisfy { $0.sequence > sequences.first! })
}

@Test func takeoverTransfersLeaseAndKeepsPageAlive() async throws {
  let (agentA, _, human) = controlContenders()
  let runtime = NativeBrowserEngine().runtime
  let (_, page, button) = try await clickablePage(runtime)
  _ = try await runtime.evaluate(pageID: page.id, source: "let retainedValue = 41")
  _ = try await runtime.scrollTo(pageID: page.id, actor: agentA, x: 0, y: 30)
  try await runtime.acquireInput(pageID: page.id, actor: agentA)
  try await runtime.takeoverInput(pageID: page.id, actor: human)
  await #expect(throws: PageControlError.inputHeld(human)) {
    try await runtime.click(pageID: page.id, actor: agentA, nodeID: button.id)
  }
  _ = try await runtime.click(pageID: page.id, actor: human, nodeID: button.id)
  #expect(try await runtime.evaluate(pageID: page.id, source: "clicks").value == "1")
  #expect(try await runtime.evaluate(pageID: page.id, source: "retainedValue + 1").value == "42")
  #expect(try await runtime.scrollOffset(pageID: page.id) == Point(x: 0, y: 30))
  let events = try await runtime.controlEvents(pageID: page.id)
  #expect(
    events.contains {
      $0.operation == "takeover" && $0.outcome == "success" && $0.detail == "agent-a"
    })
}
