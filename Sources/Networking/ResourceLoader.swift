import Foundation

public struct ResourceRequest: Hashable, Sendable {
  public var key: String
  public var url: URL
  public var documentURL: URL?

  public init(key: String, url: URL, documentURL: URL? = nil) {
    self.key = key
    self.url = url
    self.documentURL = documentURL
  }
}

public struct ResourceLoader: Sendable {
  public let network: NetworkSession

  public init(network: NetworkSession) {
    self.network = network
  }

  public func load(_ requests: [ResourceRequest]) async -> [String: Result<
    HTTPResponse, NetworkError
  >] {
    await withTaskGroup(
      of: (String, Result<HTTPResponse, NetworkError>).self,
      returning: [String: Result<HTTPResponse, NetworkError>].self
    ) { group in
      for request in requests {
        group.addTask {
          do { return (request.key, .success(try await network.fetch(HTTPRequest(url: request.url, resourceKind: .stylesheet, documentURL: request.documentURL)))) } catch let
            error as NetworkError
          { return (request.key, .failure(error)) } catch {
            return (request.key, .failure(.requestFailed(error.localizedDescription)))
          }
        }
      }
      var result: [String: Result<HTTPResponse, NetworkError>] = [:]
      for await item in group { result[item.0] = item.1 }
      return result
    }
  }
}
