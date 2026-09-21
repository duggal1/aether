import EngineCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct SuggestEndpoint: Hashable, Sendable {
  public let url: URL
  public let queryParameter: String

  public init(url: URL, queryParameter: String = "q") {
    self.url = url
    self.queryParameter = queryParameter
  }

  public func request(for query: String) -> URL? {
    guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    parts.fragment = nil
    var items = parts.queryItems ?? []
    items.removeAll { $0.name == queryParameter }
    items.append(URLQueryItem(name: queryParameter, value: query))
    parts.queryItems = items
    return parts.url
  }
}

extension SearchProvider {
  public var suggestEndpoint: SuggestEndpoint? {
    let host = (endpoint.host ?? "").lowercased()
    guard !host.isEmpty else { return nil }
    if host.contains("google.") {
      return SuggestEndpoint(
        url: URL(string: "https://suggestqueries.google.com/complete/search?client=firefox")!)
    }
    if host.contains("duckduckgo.") {
      return SuggestEndpoint(url: URL(string: "https://duckduckgo.com/ac/?type=list")!)
    }
    if host.contains("bing.") {
      return SuggestEndpoint(
        url: URL(string: "https://api.bing.com/osjson.aspx")!, queryParameter: "query")
    }
    if host.contains("brave.") {
      return SuggestEndpoint(url: URL(string: "https://search.brave.com/api/suggest")!)
    }
    return nil
  }
}

public enum SuggestEndpointResolver {
  public static func endpoint(for searchEndpoint: URL) -> SuggestEndpoint? {
    SearchProvider(endpoint: searchEndpoint).suggestEndpoint
  }
}

public protocol SuggestTransport: Sendable {
  func fetch(_ url: URL) async throws -> Data
}

public enum SuggestError: Error, Sendable {
  case status
}

public struct URLSessionSuggestTransport: SuggestTransport {
  private let session: URLSession

  public init(timeout: TimeInterval = 3) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    configuration.httpMaximumConnectionsPerHost = 2
    configuration.waitsForConnectivity = false
    configuration.httpAdditionalHeaders = [
      "Accept": "application/json, text/javascript;q=0.9, */*;q=0.5",
      "Accept-Language": "en-US,en;q=0.9",
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Aether/1.0",
    ]
    session = URLSession(configuration: configuration)
  }

  public func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw SuggestError.status
    }
    return data
  }
}

public enum SuggestResponseCodec {
  public static func completions(from data: Data, limit: Int) -> [String] {
    guard limit > 0, let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
    var raw: [String] = []
    if let items = root as? [Any] {
      if let nested = items.first(where: { $0 is [Any] }) as? [Any] {
        raw = nested.compactMap { $0 as? String }
      } else {
        raw = items.compactMap { $0 as? String }
      }
    } else if let single = root as? String {
      raw = [single]
    }
    var seen = Set<String>()
    var result: [String] = []
    result.reserveCapacity(min(limit, raw.count))
    for item in raw {
      let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      guard seen.insert(text.lowercased()).inserted else { continue }
      result.append(text)
      if result.count == limit { break }
    }
    return result
  }
}

public actor SearchSuggestService {
  public struct Snapshot: Sendable, Hashable {
    public var hits: Int
    public var misses: Int
    public var entries: Int
    public var failures: Int
  }

  private struct Entry: Sendable {
    var completions: [String]
    var storedAt: ContinuousClock.Instant
  }

  private struct Flight: Sendable {
    var token: UUID
    var task: Task<[String], Never>
  }

  private let transport: any SuggestTransport
  private let capacity: Int
  private let lifetime: Duration
  private let warmCooldown: Duration
  private var entries: [String: Entry] = [:]
  private var recency: [String] = []
  private var flights: [String: Flight] = [:]
  private var warmTimes: [String: ContinuousClock.Instant] = [:]
  private var hits = 0
  private var misses = 0
  private var failures = 0

  public init(
    transport: any SuggestTransport = URLSessionSuggestTransport(), capacity: Int = 512,
    lifetime: Duration = .seconds(300), warmCooldown: Duration = .seconds(30)
  ) {
    self.transport = transport
    self.capacity = max(16, capacity)
    self.lifetime = lifetime
    self.warmCooldown = warmCooldown
  }

  public func completions(endpoint: SuggestEndpoint, prefix: String, limit: Int = 10) async
    -> [String]
  {
    let needle = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty, limit > 0 else { return [] }
    let key = endpoint.url.absoluteString + "|" + needle.lowercased()
    if let entry = entries[key], entry.storedAt.duration(to: ContinuousClock().now) < lifetime {
      hits += 1
      markRecent(key)
      return Array(entry.completions.prefix(limit))
    }
    let token: UUID
    let task: Task<[String], Never>
    if let flight = flights[key] {
      token = flight.token
      task = flight.task
    } else {
      misses += 1
      token = UUID()
      task = Task { [transport] in
        guard let url = endpoint.request(for: needle) else { return [] }
        do { return SuggestResponseCodec.completions(from: try await transport.fetch(url), limit: 12) }
        catch { return [] }
      }
      flights[key] = Flight(token: token, task: task)
    }
    let completions = await task.value
    if let flight = flights[key], flight.token == token { flights[key] = nil }
    guard !completions.isEmpty else {
      failures += 1
      return []
    }
    store(completions, key: key)
    return Array(completions.prefix(limit))
  }

  public func warm(endpoint: SuggestEndpoint) async {
    let key = endpoint.url.absoluteString
    if let last = warmTimes[key], last.duration(to: ContinuousClock().now) < warmCooldown { return }
    warmTimes[key] = ContinuousClock().now
    _ = await completions(endpoint: endpoint, prefix: "a", limit: 1)
  }

  public func snapshot() -> Snapshot {
    Snapshot(hits: hits, misses: misses, entries: entries.count, failures: failures)
  }

  public func reset() {
    entries.removeAll()
    recency.removeAll()
    flights.removeAll()
    warmTimes.removeAll()
    hits = 0
    misses = 0
    failures = 0
  }

  private func markRecent(_ key: String) {
    if let index = recency.firstIndex(of: key) { recency.remove(at: index) }
    recency.append(key)
  }

  private func store(_ completions: [String], key: String) {
    entries[key] = Entry(completions: completions, storedAt: ContinuousClock().now)
    markRecent(key)
    while recency.count > capacity, let oldest = recency.first {
      recency.removeFirst()
      entries[oldest] = nil
    }
  }
}

