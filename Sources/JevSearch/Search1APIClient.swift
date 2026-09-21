import Foundation

public struct WebSearchResult: Sendable, Hashable {
  public let title: String
  public let link: String
  public let snippet: String
  public let publishedDate: String?

  public init(title: String, link: String, snippet: String = "", publishedDate: String? = nil) {
    self.title = title
    self.link = link
    self.snippet = snippet
    self.publishedDate = publishedDate
  }

  public var url: URL? { URL(string: link) }
  public var host: String { url?.host ?? "" }
}

extension WebSearchResult: Decodable {
  enum CodingKeys: String, CodingKey {
    case title
    case link
    case snippet
    case content
    case publishedDate = "published_date"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = (try? container.decode(String.self, forKey: .title)) ?? ""
    link = (try? container.decode(String.self, forKey: .link)) ?? ""
    let snippetValue = (try? container.decode(String.self, forKey: .snippet)) ?? ""
    let contentValue = (try? container.decode(String.self, forKey: .content)) ?? ""
    snippet = snippetValue.isEmpty ? contentValue : snippetValue
    publishedDate = try? container.decode(String.self, forKey: .publishedDate)
  }
}

public actor Search1APIClient {
  private let transport: any HTTPPostTransport
  private let endpoint: URL
  private let key: String
  private let service: String?
  private let timeout: TimeInterval

  public init(configuration: JevConfiguration, transport: any HTTPPostTransport = URLSessionTransport()) {
    self.transport = transport
    self.endpoint = configuration.searchEndpoint
    self.key = configuration.search1APIKey
    self.service = configuration.searchService
    self.timeout = configuration.timeout
  }

  public func search(query: String, limit: Int, timeRange: String? = nil) async throws
    -> [WebSearchResult]
  {
    guard !key.isEmpty else { throw JevError.notConfigured }
    var body: [String: Any] = [
      "query": query,
      "max_results": max(1, min(limit, 50)),
    ]
    if let service, !service.isEmpty { body["search_service"] = service }
    if let timeRange, !timeRange.isEmpty { body["time_range"] = timeRange }
    let payload = try JSONSerialization.data(withJSONObject: body)
    let data = try await transport.post(payload, to: endpoint, bearer: key, timeout: timeout)
    let decoder = JSONDecoder()
    if let envelope = try? decoder.decode(SearchEnvelope.self, from: data) { return envelope.results }
    if let failure = try? decoder.decode(SearchFailure.self, from: data) {
      throw JevError.transport(failure.message ?? failure.error ?? "Search1API rejected the request")
    }
    throw JevError.decoding("Unrecognized Search1API response")
  }
}

private struct SearchEnvelope: Decodable {
  let results: [WebSearchResult]
}

private struct SearchFailure: Decodable {
  let ok: Bool?
  let error: String?
  let message: String?
}
