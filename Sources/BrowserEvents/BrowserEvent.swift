import EngineCore
import Foundation

public enum BrowserEventFamily: String, Sendable, Codable, CaseIterable {
  case page
  case navigation
  case document
  case console
  case network
  case download
  case popup
  case dialog
  case permission
  case authentication
  case fileChooser
  case focus
  case context
  case branch
  case handoff
  case execution
  case lease
}

public struct BrowserEventIdentity: Hashable, Sendable, Codable {
  public var context: ContextID?
  public var page: PageID?
  public var navigation: NavigationID?
  /// Opaque to keep BrowserEvents independent from EngineRuntime's durable `BranchID`.
  public var branch: String?
  public var session: SessionID?

  public init(
    context: ContextID? = nil, page: PageID? = nil, navigation: NavigationID? = nil,
    branch: String? = nil, session: SessionID? = nil
  ) {
    self.context = context
    self.page = page
    self.navigation = navigation
    self.branch = branch
    self.session = session
  }

  public static let none = BrowserEventIdentity()
}

public enum BrowserEventKind: Sendable, Equatable {
  case pageCreated(url: String?)
  case pageClosed(reason: String)
  case navigationStarted(url: String)
  case navigationRedirected(url: String)
  case navigationCommitted(url: String, statusCode: Int)
  case navigationFinished(url: String, title: String)
  case navigationFailed(url: String?, error: String, benign: Bool)
  case urlChanged(url: String?)
  case titleChanged(title: String)
  case documentMutated(revision: UInt64)
  case consoleMessage(level: String, text: String)
  case networkNavigationResponse(url: String, statusCode: Int, mimeType: String?)
  /// Layer 1 in-page observation (directive §7.2): a request issued by page script,
  /// observed before it is sent. `bodySnippet` is bounded and redacted by the producer.
  case networkRequest(url: String, method: String, bodyBytes: Int, bodySnippet: String?)
  /// The completion of an observed request. `statusCode == 0` means the request failed
  /// before a response (CORS, network error), which is itself evidence.
  case networkResponse(
    url: String, method: String, statusCode: Int, durationMs: Int, responseBytes: Int)
  /// The observer hit its per-document cap and stopped reporting. Counted, not silent.
  case networkObservationTruncated(limit: Int)
  case downloadStarted(url: String)
  case downloadFinished(url: String, path: String?)
  case downloadFailed(url: String, error: String)
  case popupRequested(url: String)
  /// A real child web view was created and adopted the opener relationship. The page
  /// renders only because the runtime stopped returning nil from `createWebViewWith`.
  case popupOpened(url: String)
  case popupClosed(url: String)
  case dialogOpened(kind: String, message: String)
  case permissionRequested(permission: String, origin: String, decision: String)
  case authenticationChallenge(host: String, method: String)
  case fileChooserRequested(label: String?, allowsMultiple: Bool)
  case focusChanged(target: String, focused: Bool)
  case contextCreated(name: String)
  case contextDestroyed(name: String)
  case branchCreated(parent: String)
  case branchDiscarded(id: String)
  case handoffRequested(reason: String)
  case handoffParked
  case handoffResumed
  case handoffCompleted
  case handoffCancelled
  case executionStarted(id: String)
  case executionFinished(id: String, outcome: String)
  case leaseAcquired(id: String)
  case leaseRenewed(id: String)
  case leaseReleased(id: String)
  case leaseExpired(id: String)
  case leaseCancelled(id: String)

  public var family: BrowserEventFamily {
    switch self {
    case .pageCreated, .pageClosed: return .page
    case .navigationStarted, .navigationRedirected, .navigationCommitted,
      .navigationFinished, .navigationFailed: return .navigation
    case .urlChanged, .titleChanged, .documentMutated: return .document
    case .consoleMessage: return .console
    case .networkNavigationResponse, .networkRequest, .networkResponse,
      .networkObservationTruncated:
      return .network
    case .downloadStarted, .downloadFinished, .downloadFailed: return .download
    case .popupRequested, .popupOpened, .popupClosed: return .popup
    case .dialogOpened: return .dialog
    case .permissionRequested: return .permission
    case .authenticationChallenge: return .authentication
    case .fileChooserRequested: return .fileChooser
    case .focusChanged: return .focus
    case .contextCreated, .contextDestroyed: return .context
    case .branchCreated, .branchDiscarded: return .branch
    case .handoffRequested, .handoffParked, .handoffResumed, .handoffCompleted,
      .handoffCancelled: return .handoff
    case .executionStarted, .executionFinished: return .execution
    case .leaseAcquired, .leaseRenewed, .leaseReleased, .leaseExpired, .leaseCancelled:
      return .lease
    }
  }

  public var name: String {
    switch self {
    case .pageCreated: return "page.created"
    case .pageClosed: return "page.closed"
    case .navigationStarted: return "navigation.started"
    case .navigationRedirected: return "navigation.redirected"
    case .navigationCommitted: return "navigation.committed"
    case .navigationFinished: return "navigation.finished"
    case .navigationFailed: return "navigation.failed"
    case .urlChanged: return "document.urlChanged"
    case .titleChanged: return "document.titleChanged"
    case .documentMutated: return "document.mutated"
    case .consoleMessage: return "console.message"
    case .networkNavigationResponse: return "network.navigationResponse"
    case .networkRequest: return "network.request"
    case .networkResponse: return "network.response"
    case .networkObservationTruncated: return "network.truncated"
    case .downloadStarted: return "download.started"
    case .downloadFinished: return "download.finished"
    case .downloadFailed: return "download.failed"
    case .popupRequested: return "popup.requested"
    case .popupOpened: return "popup.opened"
    case .popupClosed: return "popup.closed"
    case .dialogOpened: return "dialog.opened"
    case .permissionRequested: return "permission.requested"
    case .authenticationChallenge: return "authentication.challenge"
    case .fileChooserRequested: return "fileChooser.requested"
    case .focusChanged: return "focus.changed"
    case .contextCreated: return "context.created"
    case .contextDestroyed: return "context.destroyed"
    case .branchCreated: return "branch.created"
    case .branchDiscarded: return "branch.discarded"
    case .handoffRequested: return "handoff.requested"
    case .handoffParked: return "handoff.parked"
    case .handoffResumed: return "handoff.resumed"
    case .handoffCompleted: return "handoff.completed"
    case .handoffCancelled: return "handoff.cancelled"
    case .executionStarted: return "execution.started"
    case .executionFinished: return "execution.finished"
    case .leaseAcquired: return "lease.acquired"
    case .leaseRenewed: return "lease.renewed"
    case .leaseReleased: return "lease.released"
    case .leaseExpired: return "lease.expired"
    case .leaseCancelled: return "lease.cancelled"
    }
  }

  public var details: [String: String] {
    switch self {
    case .pageCreated(let url): return ["url": url ?? ""]
    case .pageClosed(let reason): return ["reason": reason]
    case .navigationStarted(let url): return ["url": url]
    case .navigationRedirected(let url): return ["url": url]
    case .navigationCommitted(let url, let statusCode):
      return ["url": url, "statusCode": String(statusCode)]
    case .navigationFinished(let url, let title): return ["url": url, "title": title]
    case .navigationFailed(let url, let error, let benign):
      return ["url": url ?? "", "error": error, "benign": String(benign)]
    case .urlChanged(let url): return ["url": url ?? ""]
    case .titleChanged(let title): return ["title": title]
    case .documentMutated(let revision): return ["revision": String(revision)]
    case .consoleMessage(let level, let text): return ["level": level, "text": text]
    case .networkNavigationResponse(let url, let statusCode, let mimeType):
      return ["url": url, "statusCode": String(statusCode), "mimeType": mimeType ?? ""]
    case .networkRequest(let url, let method, let bodyBytes, let bodySnippet):
      return [
        "url": url, "method": method, "bodyBytes": String(bodyBytes),
        "bodySnippet": bodySnippet ?? "",
      ]
    case .networkResponse(let url, let method, let statusCode, let durationMs, let responseBytes):
      return [
        "url": url, "method": method, "statusCode": String(statusCode),
        "durationMs": String(durationMs), "responseBytes": String(responseBytes),
      ]
    case .networkObservationTruncated(let limit): return ["limit": String(limit)]
    case .downloadStarted(let url): return ["url": url]
    case .downloadFinished(let url, let path): return ["url": url, "path": path ?? ""]
    case .downloadFailed(let url, let error): return ["url": url, "error": error]
    case .popupRequested(let url): return ["url": url]
    case .popupOpened(let url): return ["url": url]
    case .popupClosed(let url): return ["url": url]
    case .dialogOpened(let kind, let message): return ["kind": kind, "message": message]
    case .permissionRequested(let permission, let origin, let decision):
      return ["permission": permission, "origin": origin, "decision": decision]
    case .authenticationChallenge(let host, let method):
      return ["host": host, "method": method]
    case .fileChooserRequested(let label, let allowsMultiple):
      return ["label": label ?? "", "allowsMultiple": String(allowsMultiple)]
    case .focusChanged(let target, let focused):
      return ["target": target, "focused": String(focused)]
    case .contextCreated(let name): return ["name": name]
    case .contextDestroyed(let name): return ["name": name]
    case .branchCreated(let parent): return ["parent": parent]
    case .branchDiscarded(let id): return ["id": id]
    case .handoffRequested(let reason): return ["reason": reason]
    case .handoffParked, .handoffResumed, .handoffCompleted, .handoffCancelled: return [:]
    case .executionStarted(let id): return ["id": id]
    case .executionFinished(let id, let outcome): return ["id": id, "outcome": outcome]
    case .leaseAcquired(let id), .leaseRenewed(let id), .leaseReleased(let id),
      .leaseExpired(let id), .leaseCancelled(let id): return ["id": id]
    }
  }
}

public struct BrowserEvent: Sendable, Equatable {
  public let sequence: UInt64
  public let timestamp: Date
  public let identity: BrowserEventIdentity
  public let kind: BrowserEventKind

  public init(sequence: UInt64, timestamp: Date, identity: BrowserEventIdentity, kind: BrowserEventKind) {
    self.sequence = sequence
    self.timestamp = timestamp
    self.identity = identity
    self.kind = kind
  }

  public var family: BrowserEventFamily { kind.family }
  public var name: String { kind.name }
  public var details: [String: String] { kind.details }
}
