import Foundation

public enum DotEnv {
  public static func parse(_ text: String) -> [String: String] {
    var values: [String: String] = [:]
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
      guard let separator = line.firstIndex(of: "=") else { continue }
      let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
      var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      if value.count >= 2, let first = value.first, let last = value.last,
        (first == "\"" && last == "\"") || (first == "'" && last == "'") {
        value = String(value.dropFirst().dropLast())
      }
      guard !key.isEmpty else { continue }
      values[key] = value
    }
    return values
  }

  public static func locate(
    fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL? {
    if let explicit = environment["AETHER_ENV_FILE"], !explicit.isEmpty {
      let url = URL(fileURLWithPath: explicit)
      if fileManager.fileExists(atPath: url.path) { return url }
    }
    let roots = [
      URL(fileURLWithPath: fileManager.currentDirectoryPath),
      Bundle.main.bundleURL,
      Bundle.main.bundleURL.deletingLastPathComponent(),
    ]
    for root in roots {
      var directory = root
      for _ in 0..<8 {
        let candidate = directory.appendingPathComponent(".env")
        if fileManager.fileExists(atPath: candidate.path) { return candidate }
        let parent = directory.deletingLastPathComponent()
        guard parent.path != directory.path else { break }
        directory = parent
      }
    }
    return nil
  }

  public static func load(
    fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> [String: String] {
    var values: [String: String] = [:]
    if let url = locate(fileManager: fileManager, environment: environment),
      let text = try? String(contentsOf: url, encoding: .utf8) {
      values = parse(text)
    }
    for key in values.keys where environment[key]?.isEmpty == false {
      values[key] = environment[key]
    }
    for (key, value) in environment where values[key] == nil && !value.isEmpty {
      values[key] = value
    }
    return values
  }
}

public struct JevConfiguration: Sendable {
  public var typeSafeKey: String
  public var search1APIKey: String
  public var model: String
  public var typeSafeEndpoint: URL
  public var searchEndpoint: URL
  public var searchService: String?
  public var resultLimit: Int
  public var timeout: TimeInterval

  public static let defaultTypeSafeEndpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
  public static let defaultSearchEndpoint = URL(string: "https://api.search1api.com/search")!
  public static let defaultModel = "jev-latest"

  public init(
    typeSafeKey: String = "", search1APIKey: String = "", model: String = JevConfiguration.defaultModel,
    typeSafeEndpoint: URL = JevConfiguration.defaultTypeSafeEndpoint,
    searchEndpoint: URL = JevConfiguration.defaultSearchEndpoint,
    searchService: String? = nil, resultLimit: Int = 10, timeout: TimeInterval = 15
  ) {
    self.typeSafeKey = typeSafeKey
    self.search1APIKey = search1APIKey
    self.model = model
    self.typeSafeEndpoint = typeSafeEndpoint
    self.searchEndpoint = searchEndpoint
    self.searchService = searchService
    self.resultLimit = max(1, min(resultLimit, 50))
    self.timeout = max(1, timeout)
  }

  public var hasIntelligence: Bool { !typeSafeKey.isEmpty }
  public var hasRetrieval: Bool { !search1APIKey.isEmpty }

  public static func load(_ dotenv: [String: String] = DotEnv.load()) -> JevConfiguration {
    func value(_ key: String, _ fallback: String) -> String {
      guard let found = dotenv[key]?.trimmingCharacters(in: .whitespaces), !found.isEmpty else { return fallback }
      return found
    }
    func optional(_ key: String) -> String? {
      guard let found = dotenv[key]?.trimmingCharacters(in: .whitespaces), !found.isEmpty else {
        return nil
      }
      return found
    }
    return JevConfiguration(
      typeSafeKey: value("TYPESAFE_API_KEY", ""),
      search1APIKey: value("SEARCH1API_API_KEY", ""),
      model: value("JEV_MODEL", defaultModel),
      typeSafeEndpoint: URL(string: value("TYPESAFE_ENDPOINT", defaultTypeSafeEndpoint.absoluteString))
        ?? defaultTypeSafeEndpoint,
      searchEndpoint: URL(string: value("SEARCH1API_ENDPOINT", defaultSearchEndpoint.absoluteString))
        ?? defaultSearchEndpoint,
      searchService: optional("SEARCH1API_SERVICE"),
      resultLimit: Int(value("JEV_SEARCH_RESULTS", "10")) ?? 10,
      timeout: TimeInterval(value("JEV_REQUEST_TIMEOUT", "15")) ?? 15)
  }
}

public protocol HTTPPostTransport: Sendable {
  func post(_ body: Data, to endpoint: URL, bearer: String, timeout: TimeInterval) async throws -> Data
}

public actor URLSessionTransport: HTTPPostTransport {
  private let session: URLSession

  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.waitsForConnectivity = false
    configuration.httpMaximumConnectionsPerHost = 4
    session = URLSession(configuration: configuration)
  }

  public func post(_ body: Data, to endpoint: URL, bearer: String, timeout: TimeInterval) async throws -> Data {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = body
    request.timeoutInterval = timeout
    request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw JevError.transport("No HTTP response") }
    guard (200..<300).contains(http.statusCode) else {
      throw JevError.status(http.statusCode, String(decoding: data.prefix(400), as: UTF8.self))
    }
    return data
  }
}
