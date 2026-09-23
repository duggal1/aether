import Foundation
import JevSearch

public enum NavigationInputError: Error, Sendable {
  case emptyInput
  case invalidURL
  case unsupportedScheme
  case invalidSearchProvider
}

public struct SearchProvider: Hashable, Sendable {
  public let endpoint: URL
  public let queryParameter: String

  public init(endpoint: URL, queryParameter: String = "q") {
    self.endpoint = endpoint
    self.queryParameter = queryParameter
  }

  public func searchURL(for query: String) throws -> URL {
    guard let scheme = endpoint.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = endpoint.host, !host.isEmpty,
      endpoint.user == nil, endpoint.password == nil,
      !queryParameter.isEmpty,
      queryParameter.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
    else { throw NavigationInputError.invalidSearchProvider }
    parts.fragment = nil
    var items = parts.queryItems ?? []
    items.removeAll { $0.name == queryParameter }
    items.append(URLQueryItem(name: queryParameter, value: query))
    parts.queryItems = items
    guard let url = parts.url else { throw NavigationInputError.invalidSearchProvider }
    return url
  }

  public static let defaultProvider = SearchProvider(
    endpoint: URL(string: "https://www.google.com/search")!)

  public static func validated(endpoint: URL, queryParameter: String) throws -> SearchProvider {
    let provider = SearchProvider(endpoint: endpoint, queryParameter: queryParameter)
    _ = try provider.searchURL(for: "validation")
    return provider
  }
}

public struct NavigationResolution: Sendable {
  public enum Kind: String, Sendable { case url, search }
  public let kind: Kind
  public let url: URL
}

public enum NavigationInputResolver {
  // One deterministic order, shared by every navigation entry point:
  //   1. explicit scheme            -> URL
  //   2. bare host / localhost / IP -> URL
  //   3. scheme-shaped but unsupported -> error
  //   4. anything else (words, questions, phrases) -> search
  // An address never becomes a search merely because it has no scheme.
  public static func resolve(
    _ input: String, provider: SearchProvider = .defaultProvider
  ) throws -> NavigationResolution {
    let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { throw NavigationInputError.emptyInput }
    if raw.contains("://") {
      guard let url = URL(string: raw) else { throw NavigationInputError.invalidURL }
      return try webURL(url)
    }
    if let direct = SearchInput.directURL(raw) {
      return try webURL(direct)
    }
    if isUnsupportedSchemeShape(raw) {
      throw NavigationInputError.unsupportedScheme
    }
    return NavigationResolution(kind: .search, url: try provider.searchURL(for: raw))
  }

  static func isUnsupportedSchemeShape(_ raw: String) -> Bool {
    guard raw.contains(":") else { return false }
    guard !raw.contains("."), !raw.contains("/"), !raw.contains("?"), !raw.contains("#")
    else { return false }
    return !SearchInput.isLocalhost(raw)
  }

  private static func webURL(_ url: URL) throws -> NavigationResolution {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme)
    else { throw NavigationInputError.unsupportedScheme }
    guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
    else { throw NavigationInputError.invalidURL }
    return NavigationResolution(kind: .url, url: url)
  }
}
