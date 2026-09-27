import BrowserEvents
import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

struct BranchHandoffTests {
  @Test func checkpointForksIndependentProfileBranchesAndDeletesChildrenFirst() async throws {
    let runtime = BrowserRuntime()
    let root = await runtime.createContext(name: "root")
    let profileDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try await runtime.openProfile(contextID: root.id, directory: profileDirectory)
    try await runtime.setCookie(
      contextID: root.id,
      cookie: CookieInfo(name: "session", value: "base", domain: "example.test", path: "/"))
    _ = try await runtime.createPage(contextID: root.id)

    let checkpoint = try await runtime.checkpointBranch(contextID: root.id)
    #expect(checkpoint.sessionPages == 1)

    let first = try await runtime.forkBranch(
      contextID: root.id, checkpointID: checkpoint.id, name: "first")
    let second = try await runtime.forkBranch(
      contextID: root.id, checkpointID: checkpoint.id, name: "second")
    #expect(first.contextID != second.contextID)
    #expect(first.websiteDataStoreID != second.websiteDataStoreID)
    #expect(first.pageCount == 1)
    #expect(second.pageCount == 1)
    let firstContext = try #require(first.contextID)
    let secondContext = try #require(second.contextID)
    #expect(try await runtime.listCookies(contextID: secondContext).contains {
      $0.name == "session" && $0.value == "base"
    })
    try await runtime.setCookie(
      contextID: firstContext,
      cookie: CookieInfo(name: "branch", value: "first", domain: "example.test", path: "/"))
    #expect(try await runtime.listCookies(contextID: secondContext).allSatisfy {
      $0.name != "branch"
    })

    let records = try await runtime.listBranches(contextID: root.id)
    #expect(records.count == 2)
    #expect(records.allSatisfy { $0.live })

    try await runtime.deleteBranch(contextID: root.id, branchID: first.id)
    #expect(try await runtime.listBranches(contextID: root.id).map(\.id) == [second.id])
    #expect(!FileManager.default.fileExists(atPath: first.directory))
  }

  @Test func handoffParksPagePersistsStateAndPublishesLifecycle() async throws {
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "handoff")
    let profileDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try await runtime.openProfile(contextID: context.id, directory: profileDirectory)
    let page = try await runtime.createPage(contextID: context.id)
    let events = await runtime.observeEvents(filter: .family(.handoff))
    let eventTask = Task { () -> [BrowserEvent] in
      var collected: [BrowserEvent] = []
      for await event in events {
        collected.append(event)
        if collected.count == 4 { break }
      }
      return collected
    }

    let request = try await runtime.requestHandoff(
      pageID: page.id, category: .mfa, reason: "Complete the sign-in challenge",
      agent: "worker-1", executionID: "exec-7")
    do {
      try await runtime.requireAgentControl(pageID: page.id)
      Issue.record("An open handoff must block agent control")
    } catch let error as HumanRequestError {
      #expect(error.code == "handoff_active")
    }
    _ = try await runtime.completeHandoff(id: request.id, by: "human")
    do {
      try await runtime.requireAgentControl(pageID: page.id)
      Issue.record("Agent control must remain parked until explicit resume")
    } catch let error as HumanRequestError {
      #expect(error.code == "handoff_active")
    }
    let resumed = try await runtime.resumeHandoff(id: request.id, by: "worker-1")
    #expect(resumed.state == .resumed)
    try await runtime.requireAgentControl(pageID: page.id)

    let emitted = await eventTask.value
    #expect(emitted.map(\.name) == [
      "handoff.requested", "handoff.parked", "handoff.completed", "handoff.resumed",
    ])
    #expect(emitted.allSatisfy { $0.identity.context == context.id && $0.identity.page == page.id })

    let reopened = BrowserRuntime()
    let reopenedContext = await reopened.createContext(name: "handoff")
    try await reopened.openProfile(contextID: reopenedContext.id, directory: profileDirectory)
    let restored = try await reopened.humanRequest(id: request.id)
    #expect(restored.state == .resumed)
    #expect(restored.page == nil)

    let interrupted = try await runtime.requestHandoff(
      pageID: page.id, category: .explicit, reason: "Finish the second human step")
    let recoveryRuntime = BrowserRuntime()
    let recoveryContext = await recoveryRuntime.createContext(name: "handoff")
    try await recoveryRuntime.openProfile(
      contextID: recoveryContext.id, directory: profileDirectory)
    let recoveredRequest = try await recoveryRuntime.humanRequest(id: interrupted.id)
    #expect(recoveredRequest.state == .interrupted)
    #expect(recoveredRequest.page == nil)
    do {
      _ = try await recoveryRuntime.resumeHandoff(id: interrupted.id)
      Issue.record("An interrupted handoff must require an explicit restored page")
    } catch let error as HumanRequestError {
      #expect(error.code == "bad_parameter")
    }
    let restoredPages = try await recoveryRuntime.listPages(contextID: recoveryContext.id)
    let recovered = try await recoveryRuntime.resumeHandoff(
      id: interrupted.id, pageID: try #require(restoredPages.first?.id))
    #expect(recovered.state == .resumed)
  }

  @Test func ephemeralHandoffStaysInMemory() async throws {
    let profileDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: profileDirectory) }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "ephemeral-handoff")
    try await runtime.openProfile(contextID: context.id, directory: profileDirectory)
    try await runtime.setContextEphemeral(contextID: context.id, enabled: true)
    let page = try await runtime.createPage(contextID: context.id)
    let request = try await runtime.requestHandoff(
      pageID: page.id, category: .mfa, reason: "Complete the private challenge")
    #expect(request.checkpointID == nil)
    #expect(try await runtime.humanRequest(id: request.id).state == .pending)

    let reopened = BrowserRuntime()
    let reopenedContext = await reopened.createContext(name: "ephemeral-handoff")
    try await reopened.openProfile(contextID: reopenedContext.id, directory: profileDirectory)
    await #expect(throws: HumanRequestError.self) {
      _ = try await reopened.humanRequest(id: request.id)
    }
  }
}
