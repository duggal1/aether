import Foundation

/// Lookup metadata for one saved login. Lives in the profile's SQLite
/// database. The secret itself is NEVER stored here — only the Keychain (or
/// the test secret store) holds it, keyed by `id`.
public struct CredentialRecord: Hashable, Sendable, Codable {
  public var id: String
  public var profileID: String
  public var origin: String
  public var username: String
  public var label: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: String = UUID().uuidString, profileID: String, origin: String, username: String,
    label: String = "", createdAt: Date = Date(), updatedAt: Date = Date()
  ) {
    self.id = id
    self.profileID = profileID
    self.origin = origin
    self.username = username
    self.label = label
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
