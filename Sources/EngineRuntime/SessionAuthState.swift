import EngineCore
import Foundation

public enum BrowserSessionState: String, Hashable, Sendable, Codable, CaseIterable {
  case notLoaded
  case loading
  case navigated
  case reauthenticationRequired
  case failed

  public var label: String {
    switch self {
    case .notLoaded: return "Not loaded"
    case .loading: return "Loading"
    case .navigated: return "Loaded"
    case .reauthenticationRequired: return "Reauthentication required"
    case .failed: return "Failed"
    }
  }
}

public struct SessionAuthClassifier: Sendable {
  public init() {}

  public func stateForCommittedPage(
    statusCode: Int, url: URL?, historyCount: Int
  ) -> BrowserSessionState {
    if statusCode == 401 || statusCode == 403 || statusCode == 407 {
      return .reauthenticationRequired
    }
    if let url, isProbableLoginURL(url), historyCount > 1 {
      return .reauthenticationRequired
    }
    return .navigated
  }

  public func isProbableLoginURL(_ url: URL) -> Bool {
    let host = url.host?.lowercased() ?? ""
    let path = url.path.lowercased()
    let query = url.query?.lowercased() ?? ""
    let haystack = host + " " + path + " " + query
    for marker in ["login", "signin", "sign-in", "log-in", "auth", "sso", "accounts"] {
      if haystack.contains(marker) { return true }
    }
    return false
  }
}

extension BrowserRuntime {
  public func sessionAuthState(pageID: PageID) -> BrowserSessionState {
    guard let state = webStates[pageID] else { return .notLoaded }
    if state.loading { return .loading }
    if state.error != nil { return .failed }
    if !state.loaded { return .notLoaded }
    return SessionAuthClassifier().stateForCommittedPage(
      statusCode: state.statusCode, url: state.url, historyCount: state.history.count)
  }

  func setWebStateForTests(_ pageID: PageID, _ state: WebPageState) {
    webStates[pageID] = state
  }
}
