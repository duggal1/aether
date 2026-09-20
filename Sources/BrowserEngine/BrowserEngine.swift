import AetherCapture
import DOM
import EngineCore
import EngineRuntime
import Foundation

public final class NativeBrowserEngine: Sendable {
  public let runtime: BrowserRuntime

  public init() {
    runtime = BrowserRuntime()
  }

  public func createContext(name: String) async -> BrowserContextInfo {
    await runtime.createContext(name: name)
  }

  public func destroyContext(_ id: ContextID) async throws {
    try await runtime.destroyContext(id)
  }

  public func createPage(contextID: ContextID, viewport: Size = Size(width: 1280, height: 800))
    async throws -> BrowserPageInfo
  {
    try await runtime.createPage(contextID: contextID, viewport: viewport)
  }

  public func navigate(pageID: PageID, url: URL) async throws -> BrowserPageInfo {
    try await runtime.navigate(pageID: pageID, to: url)
  }

  public func back(pageID: PageID) async throws -> BrowserPageInfo {
    try await runtime.goBack(pageID: pageID)
  }

  public func forward(pageID: PageID) async throws -> BrowserPageInfo {
    try await runtime.goForward(pageID: pageID)
  }

  public func reload(pageID: PageID, bypassCache: Bool = false) async throws -> BrowserPageInfo {
    try await runtime.reload(pageID: pageID, bypassCache: bypassCache)
  }

  public func inspect(pageID: PageID) async throws -> PageInspection {
    try await runtime.inspect(pageID: pageID)
  }

  public func snapshot(pageID: PageID) async throws -> PageSnapshot {
    try await runtime.snapshot(pageID: pageID)
  }

  public func query(pageID: PageID, selector: String) async throws -> InspectedNode? {
    try await runtime.query(pageID: pageID, selector: selector)
  }

  public func queryAll(pageID: PageID, selector: String) async throws -> [InspectedNode] {
    try await runtime.queryAll(pageID: pageID, selector: selector)
  }

  public func click(pageID: PageID, nodeID: NodeID) async throws -> BrowserPageInfo {
    try await runtime.click(pageID: pageID, nodeID: nodeID)
  }

  public func type(pageID: PageID, nodeID: NodeID, text: String, append: Bool = false) async throws
  {
    try await runtime.type(pageID: pageID, nodeID: nodeID, text: text, append: append)
  }

  public func evaluate(pageID: PageID, source: String) async throws -> JavaScriptResult {
    try await runtime.evaluate(pageID: pageID, source: source)
  }

  public func render(pageID: PageID) async throws -> PixelBuffer {
    try await runtime.render(pageID: pageID)
  }

  public func listContexts() async -> [BrowserContextInfo] {
    await runtime.listContexts()
  }

  public func closePage(_ pageID: PageID) async throws {
    try await runtime.closePage(pageID)
  }

  public func listPages(contextID: ContextID) async throws -> [BrowserPageInfo] {
    try await runtime.listPages(contextID: contextID)
  }

  public func pageInfo(_ pageID: PageID) async throws -> BrowserPageInfo {
    try await runtime.pageInfo(pageID)
  }

  public func resize(pageID: PageID, viewport: Size) async throws -> BrowserPageInfo {
    try await runtime.resize(pageID: pageID, viewport: viewport)
  }

  public func mutations(pageID: PageID, since version: UInt64) async throws -> [DOMMutation] {
    try await runtime.mutations(pageID: pageID, since: version)
  }

  public func waitForSelector(
    pageID: PageID, selector: String, condition: SelectorWaitCondition = .visible,
    timeoutMilliseconds: UInt64 = 5_000
  ) async throws -> InspectedNode? {
    try await runtime.waitForSelector(
      pageID: pageID, selector: selector, condition: condition,
      timeoutMilliseconds: timeoutMilliseconds)
  }

  public func setValue(pageID: PageID, nodeID: NodeID, value: String) async throws {
    try await runtime.setValue(pageID: pageID, nodeID: nodeID, value: value)
  }

  public func loadHTML(pageID: PageID, html: String, url: URL) async throws -> BrowserPageInfo {
    try await runtime.loadHTML(pageID: pageID, html: html, url: url)
  }

  public func lifecycleState(pageID: PageID) async throws -> PageLifecycleState {
    try await runtime.lifecycleState(pageID: pageID)
  }

  public func setLifecycle(pageID: PageID, state: PageLifecycleState) async throws
    -> BrowserPageInfo
  {
    try await runtime.setLifecycle(pageID: pageID, state: state)
  }

  public func restorePage(pageID: PageID) async throws -> BrowserPageInfo {
    try await runtime.restorePage(pageID: pageID)
  }

  public func fleetStats() async -> FleetStats {
    await runtime.fleetStats()
  }

  public func fleetPages() async -> [FleetPageInfo] {
    await runtime.fleetPages()
  }

  public func sweepFleet(maxActive: Int? = nil, memoryBudgetBytes: Int? = nil) async throws -> [
    PageID: PageLifecycleState
  ] {
    try await runtime.sweepFleet(maxActive: maxActive, memoryBudgetBytes: memoryBudgetBytes)
  }

  public func hover(pageID: PageID, nodeID: NodeID) async throws -> InspectedNode? {
    try await runtime.hover(pageID: pageID, nodeID: nodeID)
  }

  public func focus(pageID: PageID, nodeID: NodeID) async throws -> BrowserPageInfo {
    try await runtime.focus(pageID: pageID, nodeID: nodeID)
  }

  public func blur(pageID: PageID) async throws -> BrowserPageInfo {
    try await runtime.blur(pageID: pageID)
  }

  public func scrollTo(pageID: PageID, x: Double, y: Double) async throws -> Point {
    try await runtime.scrollTo(pageID: pageID, x: x, y: y)
  }

  public func scrollIntoView(pageID: PageID, nodeID: NodeID) async throws -> Point {
    try await runtime.scrollIntoView(pageID: pageID, nodeID: nodeID)
  }

  public func nodeAtPoint(pageID: PageID, x: Double, y: Double) async throws -> InspectedNode? {
    try await runtime.nodeAtPoint(pageID: pageID, x: x, y: y)
  }

  public func pressKey(pageID: PageID, key: String) async throws -> String {
    try await runtime.pressKey(pageID: pageID, key: key)
  }

  public func selectOption(pageID: PageID, selectNodeID: NodeID, value: String) async throws {
    try await runtime.selectOption(pageID: pageID, selectNodeID: selectNodeID, value: value)
  }

  public func fill(pageID: PageID, nodeID: NodeID, value: String) async throws {
    try await runtime.fill(pageID: pageID, nodeID: nodeID, value: value)
  }

  public func submitForm(pageID: PageID, formNodeID: NodeID) async throws -> BrowserPageInfo {
    try await runtime.submitForm(pageID: pageID, formNodeID: formNodeID)
  }

  public func historyEntries(pageID: PageID) async throws -> [HistoryEntry] {
    try await runtime.historyEntries(pageID: pageID)
  }

  public func consoleOutput(pageID: PageID) async throws -> [String] {
    try await runtime.consoleOutput(pageID: pageID)
  }

  public func networkLogEntries(pageID: PageID) async throws -> [NetworkLogEntry] {
    try await runtime.networkLogEntries(pageID: pageID)
  }

  public func listCookies(contextID: ContextID) async throws -> [CookieInfo] {
    try await runtime.listCookies(contextID: contextID)
  }

  public func setCookie(contextID: ContextID, cookie: CookieInfo) async throws {
    try await runtime.setCookie(contextID: contextID, cookie: cookie)
  }

  public func clearCookies(contextID: ContextID) async throws {
    try await runtime.clearCookies(contextID: contextID)
  }

  public func storageValues(contextID: ContextID, origin: String) async throws -> [String: String] {
    try await runtime.storageValues(contextID: contextID, origin: origin)
  }

  public func storageSet(contextID: ContextID, origin: String, key: String, value: String)
    async throws
  {
    try await runtime.storageSet(contextID: contextID, origin: origin, key: key, value: value)
  }

  public func permissionDecision(contextID: ContextID, permission: String, origin: String)
    async throws -> String
  {
    try await runtime.permissionDecision(
      contextID: contextID, permission: permission, origin: origin)
  }

  public func setPermission(
    contextID: ContextID, permission: String, origin: String, decision: String
  ) async throws {
    try await runtime.setPermission(
      contextID: contextID, permission: permission, origin: origin, decision: decision)
  }

  public func pendingDialogs(pageID: PageID) async throws -> [AgentDialogInfo] {
    try await runtime.pendingDialogs(pageID: pageID)
  }

  public func resolveDialog(id: DialogID, accept: Bool) async throws -> Bool {
    try await runtime.resolveDialog(id: id, accept: accept)
  }

  public func startDownload(contextID: ContextID, url: String, path: String?) async throws
    -> AgentDownloadInfo
  {
    try await runtime.startDownload(contextID: contextID, url: url, path: path)
  }

  public func listDownloads(contextID: ContextID) async throws -> [AgentDownloadInfo] {
    try await runtime.listDownloads(contextID: contextID)
  }

  public func openProfile(contextID: ContextID, directory: URL) async throws {
    try await runtime.openProfile(contextID: contextID, directory: directory)
  }

  public func checkpoint(contextID: ContextID) async throws {
    try await runtime.checkpoint(contextID: contextID)
  }

  public func profileUsage(contextID: ContextID) async throws -> ProfileUsage {
    try await runtime.profileUsage(contextID: contextID)
  }

  public func createSession(name: String) async -> BrowserSessionInfo {
    await runtime.createSession(name: name)
  }

  public func listSessions() async -> [BrowserSessionInfo] {
    await runtime.listSessions()
  }

  public func capturePage(
    url: URL, into directory: URL, options: CaptureOptions = CaptureOptions()
  ) async throws -> CaptureResult {
    let coordinator = CaptureCoordinator(engine: BrowserCaptureEngine(runtime: runtime))
    return try await coordinator.capture(url, into: directory, options: options)
  }
}

public typealias BrowserEngine = NativeBrowserEngine
