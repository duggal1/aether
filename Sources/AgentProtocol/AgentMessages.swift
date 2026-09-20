import Foundation

public enum AgentMethod: String, Hashable, Sendable, Codable, CaseIterable {
  case ping
  case contextCreate = "context.create"
  case contextDestroy = "context.destroy"
  case contextList = "context.list"
  case pageCreate = "page.create"
  case pageNavigate = "page.navigate"
  case pageNavigateInput = "page.navigateInput"
  case pageBack = "page.back"
  case pageForward = "page.forward"
  case pageReload = "page.reload"
  case pageResize = "page.resize"
  case pageClose = "page.close"
  case pageList = "page.list"
  case pageInspect = "page.inspect"
  case pageQuery = "page.query"
  case pageQueryAll = "page.queryAll"
  case pageFind = "page.find"
  case pageSnapshot = "page.snapshot"
  case pageWait = "page.wait"
  case pageMutations = "page.mutations"
  case pageClick = "page.click"
  case pageType = "page.type"
  case pageSetValue = "page.setValue"
  case pageEvaluate = "page.evaluate"
  case pageRender = "page.render"
  case pageMetrics = "page.metrics"
  case pageLoadHTML = "page.loadHTML"
  case pageLifecycle = "page.lifecycle"
  case pageSetLifecycle = "page.setLifecycle"
  case pageRestore = "page.restore"
  case pageHover = "page.hover"
  case pageFocus = "page.focus"
  case pageBlur = "page.blur"
  case pageFocused = "page.focused"
  case pageHovered = "page.hovered"
  case pageScroll = "page.scroll"
  case pageScrollOffset = "page.scrollOffset"
  case pageScrollIntoView = "page.scrollIntoView"
  case pageNodeAtPoint = "page.nodeAtPoint"
  case pagePressKey = "page.pressKey"
  case pageSelectOption = "page.selectOption"
  case pageFill = "page.fill"
  case pageSubmit = "page.submit"
  case pageHistory = "page.history"
  case pageConsole = "page.console"
  case pageNetworkLog = "page.networkLog"
  case pageFrame = "page.frame"
  case pageWorkers = "page.workers"
  case pageDialogs = "page.dialogs"
  case pageMedia = "page.media"
  case pageMediaControl = "page.mediaControl"
  case dialogResolve = "dialog.resolve"
  case contextCookies = "context.cookies"
  case contextSetCookie = "context.setCookie"
  case contextRemoveCookie = "context.removeCookie"
  case contextClearCookies = "context.clearCookies"
  case contextStorageOrigins = "context.storageOrigins"
  case contextStorageValues = "context.storageValues"
  case contextStorageSet = "context.storageSet"
  case contextStorageRemove = "context.storageRemove"
  case contextStorageClear = "context.storageClear"
  case contextPermission = "context.permission"
  case contextSetPermission = "context.setPermission"
  case contextPermissions = "context.permissions"
  case contextDownload = "context.download"
  case contextDownloads = "context.downloads"
  case contextClearDownloads = "context.clearDownloads"
  case contextOpenProfile = "context.openProfile"
  case contextCheckpoint = "context.checkpoint"
  case contextProfileUsage = "context.profileUsage"
  case contextSetCheckpoint = "context.setCheckpoint"
  case contextCheckpointValue = "context.checkpointValue"
  case contextBookmarkAdd = "context.bookmarkAdd"
  case contextBookmarks = "context.bookmarks"
  case contextBookmarkRemove = "context.bookmarkRemove"
  case contextSuggest = "context.suggest"
  case contextSearchProvider = "context.searchProvider"
  case contextSetSearchProvider = "context.setSearchProvider"
  case sessionCreate = "session.create"
  case sessionList = "session.list"
  case sessionDestroy = "session.destroy"
  case sessionPages = "session.pages"
  case fleetStats = "fleet.stats"
  case fleetPages = "fleet.pages"
  case fleetSweep = "fleet.sweep"
  case pageCapture = "page.capture"
}

public struct AgentRequest: Hashable, Sendable, Codable {
  public var id: String
  public var method: String
  public var params: [String: JSONValue]

  public init(
    id: String = UUID().uuidString, method: AgentMethod, params: [String: JSONValue] = [:]
  ) {
    self.id = id
    self.method = method.rawValue
    self.params = params
  }

  public init(id: String = UUID().uuidString, method: String, params: [String: JSONValue] = [:]) {
    self.id = id
    self.method = method
    self.params = params
  }
}

public struct AgentError: Hashable, Sendable, Codable {
  public var code: String
  public var message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct AgentResponse: Hashable, Sendable, Codable {
  public var id: String
  public var result: JSONValue?
  public var error: AgentError?

  public init(id: String, result: JSONValue?) {
    self.id = id
    self.result = result
    error = nil
  }

  public init(id: String, error: AgentError) {
    self.id = id
    result = nil
    self.error = error
  }

  private enum CodingKeys: String, CodingKey { case id, result, error }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    if container.contains(.result) {
      result = try container.decode(JSONValue.self, forKey: .result)
    } else {
      result = nil
    }
    error = try container.decodeIfPresent(AgentError.self, forKey: .error)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    if let result { try container.encode(result, forKey: .result) }
    if let error { try container.encode(error, forKey: .error) }
  }
}
