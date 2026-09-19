import Foundation
import Networking

public struct ImageLoader: Sendable {
  public let network: NetworkSession

  public init(network: NetworkSession) {
    self.network = network
  }

  public func load(_ url: URL) async throws -> DecodedImage {
    let response = try await network.fetch(url)
    return try ImageDecoder.decode(response.body)
  }
}
