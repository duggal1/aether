import EngineCore
import Foundation
import WebKit

struct WebCookieValue: Sendable {
  let name: String
  let value: String
  let domain: String
  let path: String
  let secure: Bool
  let httpOnly: Bool
}

struct WebCookieInput: Sendable {
  let name: String
  let value: String
  let domain: String
  let path: String
  let secure: Bool
  let httpOnly: Bool
}

@MainActor
enum WebKitCookieBridge {
  static func list(_ context: WebKitContext) async throws -> [WebCookieValue] {
    let cookies = await context.store.httpCookieStore.allCookies()
    return cookies.map { cookie in
      WebCookieValue(
        name: cookie.name, value: cookie.value, domain: cookie.domain,
        path: cookie.path, secure: cookie.isSecure, httpOnly: cookie.isHTTPOnly)
    }
  }

  static func set(_ context: WebKitContext, input: WebCookieInput) async throws {
    let properties: [HTTPCookiePropertyKey: Any] = [
      .name: input.name, .value: input.value, .domain: input.domain, .path: input.path,
      .secure: input.secure ? "TRUE" : "FALSE",
    ]
    guard let cookie = HTTPCookie(properties: properties) else {
      throw BrowserRuntimeError.invalidState("Cookie was rejected by WebKit")
    }
    await context.store.httpCookieStore.setCookie(cookie)
  }

  static func remove(
    _ context: WebKitContext, name: String, domain: String, path: String
  ) async throws {
    let cookies = await context.store.httpCookieStore.allCookies()
    for cookie in cookies where cookie.name == name
      && (cookie.domain == domain || cookie.domain == "." + domain) && cookie.path == path
    {
      await context.store.httpCookieStore.deleteCookie(cookie)
    }
  }

  static func clear(_ context: WebKitContext) async throws {
    let cookies = await context.store.httpCookieStore.allCookies()
    for cookie in cookies {
      await context.store.httpCookieStore.deleteCookie(cookie)
    }
  }
}

extension BrowserRuntime {
  func webContextForCookies(_ contextID: ContextID) async throws -> WebKitContext {
    _ = try requireContext(contextID)
    let wantEphemeral = webEphemeral.contains(contextID)
    if let existing = webContexts[contextID], existing.isEphemeral == wantEphemeral { return existing }
    let context: WebKitContext
    if wantEphemeral {
      context = await WebKitContext.ephemeral()
      webEphemeralStores[contextID] = context.store
    } else if let identifier = webProfileIdentifiers[contextID] {
      context = await WebKitContext(identifier: identifier)
    } else {
      throw BrowserRuntimeError.invalidState(
        "Profile identifier is missing for a permanent context")
    }
    let stored = webContextRules[contextID] as? WKContentRuleList
    let pendingProxy = webProxyEndpoints[contextID]
    await MainActor.run {
      context.rules = stored
      if let pendingProxy { context.apply(proxy: pendingProxy) }
    }
    webContexts[contextID] = context
    return context
  }

  public func listCookies(contextID: ContextID) async throws -> [CookieInfo] {
    let context = try await webContextForCookies(contextID)
    return try await WebKitCookieBridge.list(context).map { value in
      CookieInfo(
        name: value.name, value: value.value, domain: value.domain, path: value.path,
        secure: value.secure, httpOnly: value.httpOnly, sameSite: nil)
    }.sorted {
      if $0.domain != $1.domain { return $0.domain < $1.domain }
      return $0.name < $1.name
    }
  }

  public func setCookie(contextID: ContextID, cookie: CookieInfo) async throws {
    let context = try await webContextForCookies(contextID)
    try await WebKitCookieBridge.set(
      context,
      input: WebCookieInput(
        name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
        secure: cookie.secure, httpOnly: cookie.httpOnly))
  }

  public func removeCookie(contextID: ContextID, name: String, domain: String, path: String = "/")
    async throws
  {
    let context = try await webContextForCookies(contextID)
    try await WebKitCookieBridge.remove(context, name: name, domain: domain, path: path)
  }

  public func clearCookies(contextID: ContextID) async throws {
    let context = try await webContextForCookies(contextID)
    try await WebKitCookieBridge.clear(context)
  }
}
