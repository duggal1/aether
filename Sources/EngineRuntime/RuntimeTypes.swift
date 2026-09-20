import DOM
import Diagnostics
import EngineCore
import Foundation

public struct BrowserContextInfo: Hashable, Sendable, Codable {
  public var id: ContextID
  public var name: String
  public var pageCount: Int

  public init(id: ContextID, name: String, pageCount: Int) {
    self.id = id
    self.name = name
    self.pageCount = pageCount
  }
}

public struct BrowserPageInfo: Hashable, Sendable, Codable {
  public var id: PageID
  public var contextID: ContextID
  public var url: URL?
  public var title: String
  public var viewport: Size
  public var loaded: Bool
  public var historyIndex: Int
  public var historyCount: Int

  public init(
    id: PageID, contextID: ContextID, url: URL?, title: String, viewport: Size, loaded: Bool,
    historyIndex: Int = -1, historyCount: Int = 0
  ) {
    self.id = id
    self.contextID = contextID
    self.url = url
    self.title = title
    self.viewport = viewport
    self.loaded = loaded
    self.historyIndex = historyIndex
    self.historyCount = historyCount
  }

  public var canGoBack: Bool { historyIndex > 0 }
  public var canGoForward: Bool { historyIndex >= 0 && historyIndex + 1 < historyCount }
}

public struct InspectedNode: Hashable, Sendable, Codable {
  public var id: NodeID
  public var role: String
  public var name: String
  public var value: String?
  public var href: String?
  public var enabled: Bool
  public var editable: Bool
  public var visible: Bool
  public var bounds: Rect?

  public init(
    id: NodeID, role: String, name: String, value: String? = nil, href: String? = nil,
    enabled: Bool = true, editable: Bool = false, visible: Bool = true, bounds: Rect? = nil
  ) {
    self.id = id
    self.role = role
    self.name = name
    self.value = value
    self.href = href
    self.enabled = enabled
    self.editable = editable
    self.visible = visible
    self.bounds = bounds
  }
}

public struct PageInspection: Hashable, Sendable, Codable {
  public var page: BrowserPageInfo
  public var nodes: [InspectedNode]

  public init(page: BrowserPageInfo, nodes: [InspectedNode]) {
    self.page = page
    self.nodes = nodes
  }
}

public struct PageNodeSnapshot: Hashable, Sendable, Codable {
  public var id: NodeID
  public var parent: NodeID?
  public var children: [NodeID]
  public var kind: String
  public var tag: String?
  public var text: String?
  public var attributes: [String: String]
  public var role: String?
  public var name: String
  public var visible: Bool
  public var enabled: Bool
  public var editable: Bool
  public var bounds: Rect?

  public init(
    id: NodeID, parent: NodeID?, children: [NodeID], kind: String, tag: String?, text: String?,
    attributes: [String: String], role: String?, name: String, visible: Bool, enabled: Bool,
    editable: Bool, bounds: Rect?
  ) {
    self.id = id
    self.parent = parent
    self.children = children
    self.kind = kind
    self.tag = tag
    self.text = text
    self.attributes = attributes
    self.role = role
    self.name = name
    self.visible = visible
    self.enabled = enabled
    self.editable = editable
    self.bounds = bounds
  }
}

public struct PageSnapshot: Hashable, Sendable, Codable {
  public var page: BrowserPageInfo
  public var documentID: DocumentID
  public var mutationVersion: UInt64
  public var nodes: [PageNodeSnapshot]

  public init(
    page: BrowserPageInfo, documentID: DocumentID, mutationVersion: UInt64,
    nodes: [PageNodeSnapshot]
  ) {
    self.page = page
    self.documentID = documentID
    self.mutationVersion = mutationVersion
    self.nodes = nodes
  }
}

public enum SelectorWaitCondition: String, Hashable, Sendable, Codable {
  case attached
  case visible
  case hidden
  case detached
}

public struct JavaScriptResult: Hashable, Sendable, Codable {
  public var value: String
  public var console: [String]

  public init(value: String, console: [String]) {
    self.value = value
    self.console = console
  }
}

public struct ProfileUsage: Hashable, Sendable, Codable {
  public var databaseBytes: Int
  public var blobBytes: Int

  public init(databaseBytes: Int, blobBytes: Int) {
    self.databaseBytes = databaseBytes
    self.blobBytes = blobBytes
  }

  public var totalBytes: Int { databaseBytes + blobBytes }
}

public enum BrowserRuntimeError: Error, Sendable, CustomStringConvertible {
  case contextNotFound(ContextID)
  case pageNotFound(PageID)
  case pageNotLoaded(PageID)
  case nodeNotFound(NodeID)
  case nodeNotEditable(NodeID)
  case historyUnavailable
  case invalidNavigation(String)
  case invalidForm(String)
  case javascript(String)
  case timeout(String)
  case profileNotConfigured(ContextID)
  case lifecycleUnavailable(String)
  case dialogNotFound(DialogID)
  case downloadNotFound(DownloadID)
  case downloadBlocked(String)
  case sessionNotFound(SessionID)
  case invalidState(String)

  public var description: String {
    switch self {
    case .contextNotFound(let id): return "Context not found: \(id)"
    case .pageNotFound(let id): return "Page not found: \(id)"
    case .pageNotLoaded(let id): return "Page is not loaded: \(id)"
    case .nodeNotFound(let id): return "Node not found: \(id)"
    case .nodeNotEditable(let id): return "Node is not editable: \(id)"
    case .historyUnavailable: return "No history entry is available in that direction"
    case .invalidNavigation(let value): return value
    case .invalidForm(let value): return value
    case .javascript(let value): return value
    case .timeout(let value): return value
    case .profileNotConfigured(let id): return "No profile is open for context: \(id)"
    case .lifecycleUnavailable(let value): return value
    case .dialogNotFound(let id): return "Dialog not found: \(id)"
    case .downloadNotFound(let id): return "Download not found: \(id)"
    case .downloadBlocked(let value): return value
    case .sessionNotFound(let id): return "Session not found: \(id)"
    case .invalidState(let value): return value
    }
  }
}

public enum PageLifecycleState: String, Hashable, Sendable, Codable, CaseIterable {
  case active
  case background
  case suspended
  case frozen
  case discarded
}

public struct BrowserSessionInfo: Hashable, Sendable, Codable {
  public var id: SessionID
  public var name: String
  public var contextCount: Int
  public var createdAt: Double

  public init(id: SessionID, name: String, contextCount: Int, createdAt: Double) {
    self.id = id
    self.name = name
    self.contextCount = contextCount
    self.createdAt = createdAt
  }
}

public struct AgentDialogInfo: Hashable, Sendable, Codable {
  public var id: DialogID
  public var page: PageID
  public var kind: String
  public var message: String
  public var defaultPrompt: String?

  public init(id: DialogID, page: PageID, kind: String, message: String, defaultPrompt: String? = nil) {
    self.id = id
    self.page = page
    self.kind = kind
    self.message = message
    self.defaultPrompt = defaultPrompt
  }
}

public struct AgentDownloadInfo: Hashable, Sendable, Codable {
  public var id: DownloadID
  public var page: PageID?
  public var url: String
  public var path: String?
  public var state: String
  public var bytes: Int

  public init(
    id: DownloadID, page: PageID? = nil, url: String, path: String? = nil, state: String,
    bytes: Int = 0
  ) {
    self.id = id
    self.page = page
    self.url = url
    self.path = path
    self.state = state
    self.bytes = bytes
  }
}

public struct AgentFrameInfo: Hashable, Sendable, Codable {
  public var id: FrameID
  public var page: PageID
  public var url: String?
  public var title: String

  public init(id: FrameID, page: PageID, url: String? = nil, title: String) {
    self.id = id
    self.page = page
    self.url = url
    self.title = title
  }
}

public struct HistoryEntry: Hashable, Sendable, Codable {
  public var index: Int
  public var url: String
  public var current: Bool

  public init(index: Int, url: String, current: Bool) {
    self.index = index
    self.url = url
    self.current = current
  }
}

public struct BookmarkInfo: Hashable, Sendable, Codable {
  public var url: String
  public var title: String
  public var createdAt: Double

  public init(url: String, title: String, createdAt: Double) {
    self.url = url
    self.title = title
    self.createdAt = createdAt
  }
}

public struct NavigationSuggestion: Hashable, Sendable, Codable {
  public var kind: String
  public var url: String
  public var title: String?

  public init(kind: String, url: String, title: String? = nil) {
    self.kind = kind
    self.url = url
    self.title = title
  }
}

public struct NetworkLogEntry: Hashable, Sendable, Codable {
  public var request: RequestID
  public var navigation: NavigationID?
  public var url: String
  public var statusCode: Int
  public var durationMilliseconds: Double
  public var fromCache: Bool

  public init(
    request: RequestID, navigation: NavigationID? = nil, url: String, statusCode: Int,
    durationMilliseconds: Double, fromCache: Bool = false
  ) {
    self.request = request
    self.navigation = navigation
    self.url = url
    self.statusCode = statusCode
    self.durationMilliseconds = durationMilliseconds
    self.fromCache = fromCache
  }
}

public struct FleetPageInfo: Hashable, Sendable, Codable {
  public var page: BrowserPageInfo
  public var lifecycle: PageLifecycleState
  public var importance: Double
  public var estimatedBytes: Int

  public init(
    page: BrowserPageInfo, lifecycle: PageLifecycleState, importance: Double, estimatedBytes: Int
  ) {
    self.page = page
    self.lifecycle = lifecycle
    self.importance = importance
    self.estimatedBytes = estimatedBytes
  }
}

public struct FleetStats: Hashable, Sendable, Codable {
  public var totalContexts: Int
  public var totalPages: Int
  public var active: Int
  public var background: Int
  public var suspended: Int
  public var frozen: Int
  public var discarded: Int
  public var estimatedBytes: Int

  public init(
    totalContexts: Int, totalPages: Int, active: Int, background: Int, suspended: Int, frozen: Int,
    discarded: Int, estimatedBytes: Int
  ) {
    self.totalContexts = totalContexts
    self.totalPages = totalPages
    self.active = active
    self.background = background
    self.suspended = suspended
    self.frozen = frozen
    self.discarded = discarded
    self.estimatedBytes = estimatedBytes
  }
}

public struct CookieInfo: Hashable, Sendable, Codable {
  public var name: String
  public var value: String
  public var domain: String
  public var path: String
  public var secure: Bool
  public var httpOnly: Bool
  public var sameSite: String?

  public init(
    name: String, value: String, domain: String, path: String, secure: Bool = false,
    httpOnly: Bool = false, sameSite: String? = nil
  ) {
    self.name = name
    self.value = value
    self.domain = domain
    self.path = path
    self.secure = secure
    self.httpOnly = httpOnly
    self.sameSite = sameSite
  }
}

public struct PermissionInfo: Hashable, Sendable, Codable {
  public var origin: String
  public var permission: String
  public var decision: String

  public init(origin: String, permission: String, decision: String) {
    self.origin = origin
    self.permission = permission
    self.decision = decision
  }
}

public struct CapturePageState: Hashable, Sendable, Codable {
  public var url: URL?
  public var title: String
  public var viewport: Size
  public var documentSize: Size
  public var scroll: Point
  public var statusCode: Int

  public init(
    url: URL?, title: String, viewport: Size, documentSize: Size, scroll: Point, statusCode: Int
  ) {
    self.url = url
    self.title = title
    self.viewport = viewport
    self.documentSize = documentSize
    self.scroll = scroll
    self.statusCode = statusCode
  }
}

public struct CapturedStylesheet: Hashable, Sendable, Codable {
  public var sourceURL: String?
  public var media: String?
  public var css: String

  public init(sourceURL: String?, media: String?, css: String) {
    self.sourceURL = sourceURL
    self.media = media
    self.css = css
  }
}

public struct CapturedNode: Hashable, Sendable, Codable {
  public var selector: String
  public var tag: String
  public var role: String?
  public var text: String?
  public var bounds: Rect
  public var computedStyles: [String: String]

  public init(
    selector: String, tag: String, role: String? = nil, text: String? = nil, bounds: Rect,
    computedStyles: [String: String] = [:]
  ) {
    self.selector = selector
    self.tag = tag
    self.role = role
    self.text = text
    self.bounds = bounds
    self.computedStyles = computedStyles
  }
}

public struct CapturedResource: Hashable, Sendable, Codable {
  public var url: String
  public var kind: String

  public init(url: String, kind: String) {
    self.url = url
    self.kind = kind
  }
}

public struct CaptureIssue: Hashable, Sendable, Codable {
  public var code: String
  public var detail: String

  public init(code: String, detail: String) {
    self.code = code
    self.detail = detail
  }
}

public struct CaptureDocumentData: Hashable, Sendable, Codable {
  public var html: String
  public var stylesheets: [CapturedStylesheet]
  public var nodes: [CapturedNode]
  public var resources: [CapturedResource]
  public var issues: [CaptureIssue]

  public init(
    html: String, stylesheets: [CapturedStylesheet], nodes: [CapturedNode],
    resources: [CapturedResource], issues: [CaptureIssue] = []
  ) {
    self.html = html
    self.stylesheets = stylesheets
    self.nodes = nodes
    self.resources = resources
    self.issues = issues
  }
}
