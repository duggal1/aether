import Foundation

public struct PersistedDownload: Hashable, Sendable, Codable {
  public var id: UInt64
  public var url: String
  public var path: String?
  public var state: String
  public var bytes: Int

  public init(id: UInt64, url: String, path: String? = nil, state: String, bytes: Int = 0) {
    self.id = id
    self.url = url
    self.path = path
    self.state = state
    self.bytes = bytes
  }
}
