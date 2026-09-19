import EngineCore
import Foundation

public enum HTTPMethod: String, Hashable, Sendable, Codable {
  case get = "GET"
  case head = "HEAD"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
  case options = "OPTIONS"
}

public struct HTTPRequest: Hashable, Sendable {
  public var id: RequestID
  public var url: URL
  public var method: HTTPMethod
  public var headers: [String: String]
  public var body: Data?
  public var cachePolicy: HTTPCachePolicy

  public init(
    id: RequestID = RequestID(rawValue: 0), url: URL, method: HTTPMethod = .get,
    headers: [String: String] = [:], body: Data? = nil,
    cachePolicy: HTTPCachePolicy = .useProtocolCachePolicy
  ) {
    self.id = id
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
    self.cachePolicy = cachePolicy
  }
}

public struct HTTPResponse: Hashable, Sendable {
  public var requestID: RequestID
  public var url: URL
  public var statusCode: Int
  public var headers: [String: String]
  public var body: Data
  public var fromCache: Bool
  public var durationMilliseconds: Double

  public init(
    requestID: RequestID, url: URL, statusCode: Int, headers: [String: String], body: Data,
    fromCache: Bool = false, durationMilliseconds: Double = 0
  ) {
    self.requestID = requestID
    self.url = url
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
    self.fromCache = fromCache
    self.durationMilliseconds = durationMilliseconds
  }

  public var text: String? {
    String(data: body, encoding: .utf8) ?? String(data: body, encoding: .isoLatin1)
  }
}

public enum HTTPCachePolicy: Hashable, Sendable {
  case useProtocolCachePolicy
  case reloadIgnoringCache
  case returnCacheElseLoad
}

public enum NetworkError: Error, Sendable, CustomStringConvertible {
  case invalidResponse
  case disallowedScheme(String)
  case requestFailed(String)

  public var description: String {
    switch self {
    case .invalidResponse: return "Invalid HTTP response"
    case .disallowedScheme(let scheme): return "Disallowed URL scheme: \(scheme)"
    case .requestFailed(let message): return message
    }
  }
}
