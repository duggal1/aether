import Foundation
import JavaScript
import Networking

public struct FetchResult: Sendable {
  public var status: Int
  public var headers: [String: String]
  public var body: Data
  public var url: URL

  public init(status: Int, headers: [String: String], body: Data, url: URL) {
    self.status = status
    self.headers = headers
    self.body = body
    self.url = url
  }
}

public struct FetchAPI: Sendable {
  public let network: NetworkSession

  public init(network: NetworkSession) {
    self.network = network
  }

  public func fetch(_ url: URL) async throws -> FetchResult {
    let response = try await network.fetch(url)
    return FetchResult(
      status: response.statusCode, headers: response.headers, body: response.body, url: response.url
    )
  }
}

public struct FetchBridge: Sendable {
  public let network: NetworkSession

  public init(network: NetworkSession) {
    self.network = network
  }

  public func install(into runtime: JSRuntime) {
    runtime.asyncFetch = { [network] urlString, method, headers, bodyText in
      guard let url = URL(string: urlString), url.scheme != nil else {
        throw JSError.type("fetch URL must be a valid absolute URL")
      }
      let upper = method.uppercased()
      if upper == "TRACE" || upper == "TRACK" || upper == "CONNECT" {
        throw JSError.type("fetch method \(method) is forbidden")
      }
      let httpMethod = HTTPMethod(rawValue: upper) ?? .get
      let request = HTTPRequest(
        url: url, method: httpMethod, headers: headers,
        body: bodyText?.data(using: .utf8))
      let response = try await network.fetch(request)
      return (response.statusCode, response.headers, response.body)
    }
  }
}
