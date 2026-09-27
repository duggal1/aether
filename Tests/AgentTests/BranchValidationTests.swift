import AgentProtocol
import BrowserEngine
import BrowserEvents
import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

/// Testing Agent 1 — validation of branchable browser contexts.
/// Uses a real local HTTP origin so cookies and localStorage are genuine WebKit state.
struct BranchValidationTests {
  private func uuidDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  /// Builds state S42: a persistent context with cookies and localStorage set by a
  /// real page script, then checkpoints it.
  private func makeS42(
    port: UInt16, runtime: BrowserRuntime = BrowserRuntime()
  ) async throws -> (BrowserRuntime, ContextID, URL, BranchCheckpointSummary) {
    let context = await runtime.createContext(name: "s42")
    let directory = uuidDirectory()
    try await runtime.openProfile(contextID: context.id, directory: directory)
    try await runtime.setCookie(
      contextID: context.id,
      cookie: CookieInfo(name: "baseline", value: "base", domain: "127.0.0.1", path: "/"))
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.navigate(
      pageID: page.id, to: ValidationFixtureServer.url(port, "/set-cookie-only"))
    _ = try await runtime.evaluate(
      pageID: page.id, source: "localStorage.setItem('token','parent-value')")
    // Leave the checkpointed URL on a page that neither reads nor writes storage, so a
    // branch reading localStorage later reflects real cloning, not the page's own script.
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(port, "/fast"))
    let checkpoint = try await runtime.checkpointBranch(contextID: context.id)
    return (runtime, context.id, directory, checkpoint)
  }

  private func firstPage(_ runtime: BrowserRuntime, _ contextID: ContextID) async throws -> PageID {
    guard let page = try await runtime.listPages(contextID: contextID).first else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    return page.id
  }

  /// Fork restores its pages in the `.discarded` lifecycle, so a consumer must
  /// restore before any navigate/evaluate/exec. Tracked as TISSUE-003.
  private func restoreIfDiscarded(_ runtime: BrowserRuntime, _ page: PageID) async throws {
    if try await runtime.lifecycleState(pageID: page) == .discarded {
      _ = try await runtime.restorePage(pageID: page)
    }
  }

  private func localToken(_ runtime: BrowserRuntime, page: PageID) async throws -> String {
    try await runtime.evaluate(pageID: page, source: "localStorage.getItem('token') || 'none'").value
  }

  @Test @MainActor func checkpointForksThreeIndependentBranches() async throws {
    let server = try ValidationFixtureServer.start(port: 18951)
    defer { server.terminate() }
    let (runtime, root, directory, checkpoint) = try await makeS42(port: 18951)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(checkpoint.localStorageEntries >= 1, "checkpoint missed live localStorage")
    #expect(checkpoint.cookies >= 2)

    let a = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "branch-a")
    let b = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "branch-b")
    let c = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "branch-c")
    #expect(Set([a.contextID, b.contextID, c.contextID]).count == 3)
    #expect(Set([a.websiteDataStoreID, b.websiteDataStoreID, c.websiteDataStoreID]).count == 3)
    #expect(Set([a.id, b.id, c.id]).count == 3)
    #expect(try await runtime.listBranches(contextID: root).count == 3)
    #expect(a.parentBranchID == nil)
    #expect(a.websiteDataStoreID == a.id.rawValue)

    let contextA = try #require(a.contextID)
    let contextB = try #require(b.contextID)
    let contextC = try #require(c.contextID)
    let pageA = try await firstPage(runtime, contextA)
    let pageB = try await firstPage(runtime, contextB)
    let pageC = try await firstPage(runtime, contextC)
    // A fork returns hibernated pages; using one without restoring fails hard, and the
    // report names exactly which pages those are.
    #expect(try await runtime.lifecycleState(pageID: pageA) == .discarded)
    #expect(a.restoreRequiredPages == [String(pageA.rawValue)])
    try await restoreIfDiscarded(runtime, pageA)
    try await restoreIfDiscarded(runtime, pageB)
    try await restoreIfDiscarded(runtime, pageC)
    _ = try await runtime.navigate(pageID: pageA, to: ValidationFixtureServer.url(18951, "/state-read"))
    _ = try await runtime.navigate(pageID: pageB, to: ValidationFixtureServer.url(18951, "/state-read"))
    _ = try await runtime.navigate(pageID: pageC, to: ValidationFixtureServer.url(18951, "/state-read"))

    // Cookies are seeded into each branch's WebKit store: cloned and isolated.
    for context in [contextA, contextB, contextC] {
      let cookies = try await runtime.listCookies(contextID: context)
      #expect(cookies.contains { $0.name == "session" && $0.value == "abc" })
      #expect(cookies.contains { $0.name == "baseline" })
    }
    // Known limitation: WebKit localStorage is NOT auto-rehydrated on a fork, and
    // the branch must report that honestly instead of claiming a full clone.
    #expect(try await localToken(runtime, page: pageA) == "none")
    #expect(a.bestEffortState.contains("localStorageRehydratedOnOriginVisit") == false)
    #expect(a.notClonedState.contains("localStorageAutoRehydration"))

    // Mutate A only: localStorage and a fresh cookie.
    _ = try await runtime.evaluate(pageID: pageA, source: "localStorage.setItem('token','A')")
    try await runtime.setCookie(
      contextID: contextA,
      cookie: CookieInfo(name: "only-a", value: "1", domain: "127.0.0.1", path: "/"))
    #expect(try await localToken(runtime, page: pageA) == "A")
    // B and C must not inherit A's localStorage or cookie changes.
    #expect(try await localToken(runtime, page: pageB) == "none")
    #expect(try await localToken(runtime, page: pageC) == "none")
    #expect(try await runtime.listCookies(contextID: contextB).allSatisfy { $0.name != "only-a" })
    #expect(try await runtime.listCookies(contextID: contextC).allSatisfy { $0.name != "only-a" })
    #expect(try await runtime.listCookies(contextID: contextA).contains { $0.name == "only-a" })

    // Delete A (no children); its directory and record vanish, B/C survive.
    try await runtime.deleteBranch(contextID: root, branchID: a.id)
    #expect(!FileManager.default.fileExists(atPath: a.directory))
    #expect(try await runtime.listBranches(contextID: root).map(\.id) == [b.id, c.id])
    #expect(try await runtime.listBranches(contextID: root).count == 2)
  }

  @Test @MainActor func forkOfForkRecordsAncestryAndDeletesChildrenFirst() async throws {
    let server = try ValidationFixtureServer.start(port: 18952)
    defer { server.terminate() }
    let (runtime, root, directory, checkpoint) = try await makeS42(port: 18952)
    defer { try? FileManager.default.removeItem(at: directory) }
    let a = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "a")
    let contextA = try #require(a.contextID)
    let pageA = try await firstPage(runtime, contextA)
    try await restoreIfDiscarded(runtime, pageA)
    _ = try await runtime.navigate(pageID: pageA, to: ValidationFixtureServer.url(18952, "/fast"))
    let checkpointA = try await runtime.checkpointBranch(contextID: contextA)
    let a2 = try await runtime.forkBranch(contextID: contextA, checkpointID: checkpointA.id, name: "a2")
    #expect(a2.parentBranchID == a.id)

    // The root sees the whole tree, not only its direct children: a supervisor forking a
    // branch-of-a-branch must be able to enumerate descendants from the root (TISSUE-004).
    #expect(try await runtime.listBranches(contextID: root).map(\.id) == [a.id, a2.id])
    let childRecords = try await runtime.listBranches(contextID: contextA)
    #expect(childRecords.map(\.id) == [a2.id])
    #expect(childRecords.first?.parentBranchID == a.id)

    // Deleting a branch with a child must fail rather than orphan the child, from either
    // endpoint of the ancestry.
    do {
      try await runtime.deleteBranch(contextID: root, branchID: a.id)
      Issue.record("deleting a parent with children unexpectedly succeeded")
    } catch let error as BranchError {
      guard case .hasChildren = error else {
        Issue.record("expected hasChildren, got \(error)")
        return
      }
    }

    // The record of a grandchild lives in its parent branch's index; the root still owns
    // deleting it and the removal must land in that index (TISSUE-004).
    try await runtime.deleteBranch(contextID: root, branchID: a2.id)
    #expect(!FileManager.default.fileExists(atPath: a2.directory))
    #expect(try await runtime.listBranches(contextID: contextA).isEmpty)
    #expect(try await runtime.listBranches(contextID: root).map(\.id) == [a.id])

    try await runtime.deleteBranch(contextID: root, branchID: a.id)
    #expect(try await runtime.listBranches(contextID: root).isEmpty)
  }

  /// The fork report must state which pages still have to be activated, so a consumer never
  /// discovers it by hitting `Page is discarded` mid-program (TISSUE-003).
  @Test @MainActor func forkReportNamesPagesRequiringRestore() async throws {
    let server = try ValidationFixtureServer.start(port: 18958)
    defer { server.terminate() }
    let (runtime, root, directory, checkpoint) = try await makeS42(port: 18958)
    defer { try? FileManager.default.removeItem(at: directory) }

    let a = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "restore-a")
    let contextA = try #require(a.contextID)
    let pageA = try await firstPage(runtime, contextA)
    #expect(a.restoreRequiredPages == [String(pageA.rawValue)])
    #expect(a.pageMap.values.contains(String(pageA.rawValue)))

    // Driving a hibernated branch page without restoring fails, and says why.
    await #expect(throws: BrowserRuntimeError.self) {
      _ = try await runtime.evaluate(pageID: pageA, source: "document.title")
    }

    try await restoreIfDiscarded(runtime, pageA)
    let listed = try await runtime.listBranches(contextID: contextA)
    #expect(listed.isEmpty, "a branch is indexed in its parent profile, not its own")
    #expect(try await runtime.listBranches(contextID: root).first?.restoreRequiredPages == [])
  }

  @Test @MainActor func branchRecordsSurviveRuntimeRestart() async throws {
    let server = try ValidationFixtureServer.start(port: 18953)
    defer { server.terminate() }
    let (runtime, root, directory, checkpoint) = try await makeS42(port: 18953)
    defer { try? FileManager.default.removeItem(at: directory) }
    let a = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "persist-a")
    let contextA = try #require(a.contextID)
    try await runtime.setCookie(
      contextID: contextA,
      cookie: CookieInfo(name: "persisted", value: "yes", domain: "127.0.0.1", path: "/"))

    // New process-equivalent runtime over the same profile directory.
    let reopened = BrowserRuntime()
    let reopenedContext = await reopened.createContext(name: "s42")
    try await reopened.openProfile(contextID: reopenedContext.id, directory: directory)
    let restored = try await reopened.listBranches(contextID: reopenedContext.id)
    #expect(restored.count == 1)
    let record = try #require(restored.first)
    #expect(record.id == a.id)
    #expect(record.name == "persist-a")
    #expect(record.live == false)
    #expect(record.checkpoint.cookies >= 2)
    #expect(record.websiteDataStoreID == a.websiteDataStoreID)
    #expect(FileManager.default.fileExists(atPath: record.directory))
  }

  @Test @MainActor func invalidAndCorruptBranchOperationsFailCleanly() async throws {
    let server = try ValidationFixtureServer.start(port: 18954)
    defer { server.terminate() }
    let (runtime, root, directory, checkpoint) = try await makeS42(port: 18954)
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(throws: BranchError.self) {
      _ = try await runtime.forkBranch(
        contextID: root, checkpointID: BranchCheckpointID(), name: "ghost")
    }
    await #expect(throws: BranchError.self) {
      try await runtime.deleteBranch(contextID: root, branchID: BranchID())
    }
    await #expect(throws: BranchError.self) {
      _ = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "   ")
    }
    await #expect(throws: BrowserRuntimeError.self) {
      _ = try await runtime.forkBranch(
        contextID: ContextID(rawValue: 9_999_999), checkpointID: checkpoint.id, name: "nope")
    }

    let ephemeral = await runtime.createContext(name: "private")
    let ephemeralDirectory = uuidDirectory()
    try await runtime.openProfile(contextID: ephemeral.id, directory: ephemeralDirectory)
    try await runtime.setContextEphemeral(contextID: ephemeral.id, enabled: true)
    await #expect(throws: BranchError.self) {
      _ = try await runtime.checkpointBranch(contextID: ephemeral.id)
    }
    try? FileManager.default.removeItem(at: ephemeralDirectory)
  }

  @Test @MainActor func branchLifecyclePublishesBranchIdentityEvents() async throws {
    let server = try ValidationFixtureServer.start(port: 18955)
    defer { server.terminate() }
    let (runtime, root, directory, checkpoint) = try await makeS42(port: 18955)
    defer { try? FileManager.default.removeItem(at: directory) }
    let stream = await runtime.observeEvents(filter: .family(.branch))
    let collector = Task { () -> [BrowserEvent] in
      var out: [BrowserEvent] = []
      for await event in stream {
        out.append(event)
        if out.count == 2 { break }
      }
      return out
    }
    let a = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "evt-a")
    let contextA = try #require(a.contextID)
    try await runtime.deleteBranch(contextID: root, branchID: a.id)
    let events = await collector.value
    #expect(events.map(\.name) == ["branch.created", "branch.discarded"])
    #expect(events.allSatisfy { $0.identity.branch == a.id.description })
    // Both lifecycle events carry the branch's own (attached) context, so a consumer can
    // follow one context identity across `branch.created` and `branch.discarded` (TISSUE-005).
    #expect(events.first?.identity.context == contextA)
    #expect(events.last?.identity.context == contextA)
  }

  /// Fork cost must be proportional to checkpoint content, not a copy of the
  /// parent's whole profile. Measures on-disk duplication honestly.
  @Test @MainActor func forkStorageCostIsBounded() async throws {
    let server = try ValidationFixtureServer.start(port: 18956)
    defer { server.terminate() }
    let (runtime, root, directory, checkpoint) = try await makeS42(port: 18956)
    defer { try? FileManager.default.removeItem(at: directory) }
    let a = try await runtime.forkBranch(contextID: root, checkpointID: checkpoint.id, name: "size-a")
    let parentSize = directorySize(directory)
    let branchSize = directorySize(URL(fileURLWithPath: a.directory))
    print("[branch-cost] parent=\(parentSize)B branchA=\(branchSize)B")
    #expect(branchSize > 0)
    #expect(branchSize <= parentSize * 2, "branch \(branchSize)B vs parent \(parentSize)B")
  }

  @Test @MainActor func execProgramRetargetsOntoForkedBranchPage() async throws {
    let server = try ValidationFixtureServer.start(port: 18957)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let runtime = engine.runtime
    let context = await runtime.createContext(name: "s42")
    let directory = uuidDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await runtime.openProfile(contextID: context.id, directory: directory)
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(18957, "/state"))
    let checkpoint = try await runtime.checkpointBranch(contextID: context.id)
    let branch = try await runtime.forkBranch(
      contextID: context.id, checkpointID: checkpoint.id, name: "exec-branch")
    let pageMap = branch.pageMap
    #expect(pageMap.count == 1)
    let branchPageRaw = try #require(pageMap.values.first)
    let branchPage = PageID(rawValue: UInt64(branchPageRaw) ?? 0)
    // A forked page arrives hibernated and the report says so; the program itself restores
    // it with a `restore` step, so an agent never needs a second RPC to activate a branch
    // (TISSUE-003).
    #expect(branch.restoreRequiredPages == [branchPageRaw])

    let outcome = await AgentExecRuntime(engine: engine).run(
      ExecProgram(steps: [
        .set(name: "pg", value: .literal(.number(Double(branchPage.rawValue)))),
        .restore(page: .ref("pg"), into: "restored"),
        .evaluate(page: .ref("pg"), source: .literal(.string("document.title")), into: "t"),
        .result(value: .ref("t.value")),
      ]))
    #expect(outcome.status == .completed, "\(outcome.error?.message ?? "")")
    #expect(outcome.operations == 2)
    #expect(outcome.results.count == 1)
  }

  private func directorySize(_ url: URL) -> Int {
    guard let enumerator = FileManager.default.enumerator(
      at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total = 0
    for case let file as URL in enumerator {
      total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    return total
  }
}
