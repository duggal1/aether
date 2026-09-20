import Foundation
import Networking

public struct ImageLoader: Sendable {
  public let network: NetworkSession

  public init(network: NetworkSession) {
    self.network = network
  }

  public func load(_ url: URL, documentURL: URL? = nil) async throws -> DecodedImage {
    let response = try await network.fetch(HTTPRequest(url: url, resourceKind: .image, documentURL: documentURL))
    return try ImageDecoder.decode(response.body)
  }
}
