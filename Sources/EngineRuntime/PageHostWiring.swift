import CSS
import DOM
import EngineCore
import Foundation
import Networking
import Style
import Synchronization
import WebSecurity

final class LiveViewport: @unchecked Sendable {
  private let state: Mutex<Size>

  init(_ size: Size) {
    state = Mutex(size)
  }

  var size: Size {
    get { state.withLock { $0 } }
    set { state.withLock { $0 = newValue } }
  }
}

final class SharedStyledDocument: @unchecked Sendable {
  private let state: Mutex<StyledDocument?>

  init(_ styled: StyledDocument? = nil) {
    state = Mutex(styled)
  }

  var styled: StyledDocument? {
    get { state.withLock { $0 } }
    set { state.withLock { $0 = newValue } }
  }
}

final class PendingPageAction: @unchecked Sendable {
  private let state: Mutex<(navigation: URL?, submit: NodeID?)>

  init() {
    state = Mutex((nil, nil))
  }

  func requestNavigation(_ url: URL) {
    state.withLock { $0.navigation = url }
  }

  func requestSubmit(_ form: NodeID) {
    state.withLock { $0.submit = form }
  }

  func take() -> (navigation: URL?, submit: NodeID?) {
    state.withLock {
      let pending = $0
      $0 = (nil, nil)
      return pending
    }
  }
}

enum FetchHostError: Error, Sendable, CustomStringConvertible {
  case invalidURL(String)
  case blocked(String)
  case transport(String)

  var description: String {
    switch self {
    case .invalidURL(let value): return "fetch URL is invalid: \(value)"
    case .blocked(let value): return value
    case .transport(let value): return value
    }
  }
}

enum PageHostWiring {
  static let userAgent = "NativeBrowserEngine/0.1"

  static func fetchHandler(
    network: NetworkSession, pageURL: URL, pageOrigin: Origin
  ) -> (@Sendable (String, String, [String: String], String?) async throws -> (
    Int, [String: String], Data
  )) {
    { urlString, method, headerMap, bodyText in
      guard let url = URL(string: urlString) else {
        throw FetchHostError.invalidURL(urlString)
      }
      guard NavigationPolicy.allowsSubresource(url) else {
        throw FetchHostError.blocked("fetch scheme blocked \(url.scheme ?? "")")
      }
      guard MixedContent.decision(pageURL: pageURL, resourceURL: url) != .block else {
        throw FetchHostError.blocked("mixed content blocked \(url.absoluteString)")
      }
      let sameOrigin =
        Origin(url: url).map { $0.isSameOrigin(as: pageOrigin) } ?? false
      // Scripts cannot forge browser-controlled credentials or origin identity.
      let forbidden: Set<String> = ["cookie", "cookie2", "host", "origin", "referer",
        "access-control-request-method", "access-control-request-headers"]
      guard !headerMap.keys.contains(where: { forbidden.contains($0.lowercased()) }) else {
        throw FetchHostError.blocked("fetch cannot set forbidden browser-controlled headers")
      }
      let unsafeHeaders = headerMap.filter {
        !CORSPolicy.isSafelistedRequestHeader(name: $0.key, value: $0.value)
      }
      let needsPreflight = !CORSPolicy.isSimpleMethod(method) || !unsafeHeaders.isEmpty
      if !sameOrigin, needsPreflight {
        let preflightHeaders = [
          "Origin": pageOrigin.description,
          "Access-Control-Request-Method": method.uppercased(),
          "Access-Control-Request-Headers": unsafeHeaders.keys.sorted().joined(separator: ", "),
        ]
        let preflight = try await network.fetch(
          HTTPRequest(url: url, method: .options, headers: preflightHeaders,
            sendsCookies: false))
        guard (200..<300).contains(preflight.statusCode) else {
          throw FetchHostError.blocked("CORS preflight failed with HTTP \(preflight.statusCode)")
        }
        if case .deny(let reason) = CORSPolicy.checkResponse(
          requestOrigin: pageOrigin, responseHeaders: preflight.headers,
          allowsCredentials: false)
        {
          throw FetchHostError.blocked("CORS preflight origin denied: \(reason)")
        }
        switch CORSPolicy.checkPreflight(
          method: method, headers: Array(headerMap.keys),
          responseHeaders: preflight.headers)
        {
        case .allow: break
        case .deny(let reason): throw FetchHostError.blocked("CORS preflight denied: \(reason)")
        }
      }
      var headers = headerMap
      if !sameOrigin { headers["Origin"] = pageOrigin.description }
      if sameOrigin {
        let context = CookieRequestContext(topLevelHost: pageOrigin.host, method: method)
        if headers["Cookie"] == nil,
          let cookie = network.cookieJar.header(for: url, context: context)
        {
          headers["Cookie"] = cookie
        }
      }
      guard let httpMethod = HTTPMethod(rawValue: method.uppercased()) else {
        throw FetchHostError.blocked("Unsupported fetch method \(method)")
      }
      let body = bodyText.flatMap { $0.data(using: .utf8) }
      let response: HTTPResponse
      do {
        response = try await network.fetch(
          HTTPRequest(url: url, method: httpMethod, headers: headers, body: body,
            sendsCookies: sameOrigin))
      } catch {
        throw FetchHostError.transport(String(describing: error))
      }
      guard MixedContent.decision(pageURL: pageURL, resourceURL: response.url) != .block
      else { throw FetchHostError.blocked("mixed content redirect blocked") }
      let finalSameOrigin =
        Origin(url: response.url).map { $0.isSameOrigin(as: pageOrigin) } ?? false
      if !finalSameOrigin {
        switch CORSPolicy.checkResponse(
          requestOrigin: pageOrigin, responseHeaders: response.headers,
          allowsCredentials: false)
        {
        case .allow: break
        case .deny(let reason): throw FetchHostError.blocked("CORS denied: \(reason)")
        }
      }
      return (response.statusCode, safelistedHeaders(response.headers), response.body)
    }
  }

  static func safelistedHeaders(_ headers: [String: String]) -> [String: String] {
    let safelisted: Set<String> = [
      "cache-control", "content-language", "content-type", "expires", "last-modified", "pragma",
    ]
    var exposed = safelisted
    for (name, value) in headers where name.lowercased() == "access-control-expose-headers" {
      for part in value.split(separator: ",") {
        exposed.insert(
          part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
      }
    }
    var result: [String: String] = [:]
    for (name, value) in headers where exposed.contains(name.lowercased()) {
      result[name.lowercased()] = value
    }
    return result
  }

  static func computedStyleValue(_ style: ComputedStyle, property: String) -> String? {
    switch property.lowercased() {
    case "display":
      return style.display == .inlineBlock ? "inline-block" : style.display.rawValue
    case "position": return style.position.rawValue
    case "color": return cssColor(style.color)
    case "background-color": return cssColor(style.backgroundColor)
    case "font-size": return "\(style.fontSize)px"
    case "font-weight": return String(style.fontWeight)
    case "font-family": return style.fontFamily
    case "line-height": return String(style.lineHeight)
    case "visibility": return style.visibility.rawValue
    case "opacity": return String(style.opacity)
    case "z-index": return String(style.zIndex)
    case "flex-direction": return style.flexDirection.rawValue
    case "overflow": return style.overflowX == style.overflowY ? style.overflowX.rawValue : nil
    case "overflow-x": return style.overflowX.rawValue
    case "overflow-y": return style.overflowY.rawValue
    case "width": return cssLength(style.width)
    case "height": return cssLength(style.height)
    case "min-width": return cssLength(style.minWidth)
    case "max-width": return cssLength(style.maxWidth)
    case "left": return cssLength(style.left)
    case "top": return cssLength(style.top)
    case "content-visibility": return style.contentVisibility.rawValue
    default: return nil
    }
  }

  static func cssColor(_ color: RGBAColor) -> String {
    let (r, g, b, a) = color.rgba8
    if a == 255 { return String(format: "#%02x%02x%02x", r, g, b) }
    return "rgba(\(r), \(g), \(b), \(Double(a) / 255))"
  }

  static func cssLength(_ length: CSSLength) -> String? {
    switch length {
    case .auto: return "auto"
    case .px(let v): return "\(v)px"
    case .percent(let v): return "\(v)%"
    case .em(let v): return "\(v)em"
    case .rem(let v): return "\(v)rem"
    case .viewportWidth(let v): return "\(v)vw"
    case .viewportHeight(let v): return "\(v)vh"
    case .viewportMin(let v): return "\(v)vmin"
    case .viewportMax(let v): return "\(v)vmax"
    case .ch(let v): return "\(v)ch"
    }
  }
}
