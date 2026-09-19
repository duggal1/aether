import EngineCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public actor NetworkSession {
  private let session: URLSession
  private let counter = AtomicCounter()
  public nonisolated let cookieJar: CookieJar
  public let cache: HTTPCache

  public init(cacheBytes: Int = 64 * 1024 * 1024) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 60
    configuration.httpMaximumConnectionsPerHost = 8
    session = URLSession(configuration: configuration)
    cookieJar = CookieJar()
    cache = HTTPCache(maximumBytes: cacheBytes)
  }

  public func fetch(_ input: HTTPRequest) async throws -> HTTPResponse {
    guard let scheme = input.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      throw NetworkError.disallowedScheme(input.url.scheme ?? "")
    }

    var request = input
    if request.id.rawValue == 0 { request.id = RequestID(rawValue: counter.next()) }

    if request.method == .get, request.cachePolicy != .reloadIgnoringCache,
      let cached = await cache.response(for: request.url)
    {
      return cached
    }

    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method.rawValue
    urlRequest.httpBody = request.body
    for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
    if urlRequest.value(forHTTPHeaderField: "User-Agent") == nil {
      urlRequest.setValue("NativeBrowserEngine/0.1", forHTTPHeaderField: "User-Agent")
    }
    if let cookie = cookieJar.header(for: request.url),
      urlRequest.value(forHTTPHeaderField: "Cookie") == nil
    {
      urlRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
    }

    let clock = ContinuousClock()
    let start = clock.now
    do {
      let (data, response) = try await session.data(for: urlRequest)
      guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
      let duration = start.duration(to: clock.now)
      let millis =
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
      var headers: [String: String] = [:]
      for (key, value) in http.allHeaderFields {
        headers[String(describing: key)] = String(describing: value)
      }
      if let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") {
        cookieJar.absorb(setCookie: setCookie, from: http.url ?? request.url)
      }
      let result = HTTPResponse(
        requestID: request.id,
        url: http.url ?? request.url,
        statusCode: http.statusCode,
        headers: headers,
        body: data,
        fromCache: false,
        durationMilliseconds: millis
      )
      if request.method == .get { await cache.store(result) }
      return result
    } catch let error as NetworkError {
      throw error
    } catch {
      throw NetworkError.requestFailed(error.localizedDescription)
    }
  }

  public func fetch(_ url: URL) async throws -> HTTPResponse {
    try await fetch(HTTPRequest(url: url))
  }

  public nonisolated func snapshotCookies() -> [Cookie] {
    cookieJar.all()
  }

  public nonisolated func restoreCookies(_ cookies: [Cookie]) {
    cookieJar.clear()
    for cookie in cookies { cookieJar.store(cookie) }
  }

  public func snapshotCache() async -> [CacheSnapshot] {
    await cache.snapshot()
  }

  public func restoreCache(_ snapshots: [CacheSnapshot]) async {
    for snapshot in snapshots { await cache.restore(snapshot) }
  }
}
