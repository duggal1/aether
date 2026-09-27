import Foundation
import Security

/// Secret storage seam for agent-readable credentials. Production uses the
/// macOS Keychain (same `fun.aether.secure-storage` service as
/// `AetherKeychain`; account namespace `"<profileUUID>:credential:<id>"`
/// cannot collide with `proxy:<endpointID>` accounts). Tests inject the
/// ephemeral in-memory store so no Keychain or UI layer is involved.
public protocol CredentialSecretStoring: Sendable {
  func saveSecret(_ secret: String, profileID: String, credentialID: String) throws
  func loadSecret(profileID: String, credentialID: String) throws -> String?
  func deleteSecret(profileID: String, credentialID: String) throws
}

public enum CredentialSecretError: Error, Sendable, CustomStringConvertible {
  case invalidData
  case keychain(OSStatus)

  public var description: String {
    switch self {
    case .invalidData: return "Credential secret could not be encoded."
    case .keychain(let status): return "Keychain refused the credential request (status \(status))."
    }
  }
}

public struct KeychainCredentialSecrets: CredentialSecretStoring {
  public static let service = "fun.aether.secure-storage"
  public init() {}

  public static func account(profileID: String, credentialID: String) -> String {
    "\(profileID):credential:\(credentialID)"
  }

  public func saveSecret(_ secret: String, profileID: String, credentialID: String) throws {
    guard let data = secret.data(using: .utf8) else { throw CredentialSecretError.invalidData }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: Self.account(profileID: profileID, credentialID: credentialID),
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw CredentialSecretError.keychain(status) }
    var insertion = query
    for (key, entry) in attributes { insertion[key] = entry }
    let added = SecItemAdd(insertion as CFDictionary, nil)
    guard added == errSecSuccess else { throw CredentialSecretError.keychain(added) }
  }

  public func loadSecret(profileID: String, credentialID: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: Self.account(profileID: profileID, credentialID: credentialID),
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data,
      let text = String(data: data, encoding: .utf8)
    else { throw CredentialSecretError.keychain(status) }
    return text
  }

  public func deleteSecret(profileID: String, credentialID: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: Self.account(profileID: profileID, credentialID: credentialID),
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialSecretError.keychain(status)
    }
  }
}

/// In-memory secret store for tests. Never touches the Keychain.
public final class EphemeralCredentialSecrets: CredentialSecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]
  public init() {}

  private func key(profileID: String, credentialID: String) -> String {
    "\(profileID):\(credentialID)"
  }

  public func saveSecret(_ secret: String, profileID: String, credentialID: String) throws {
    lock.withLock { values[key(profileID: profileID, credentialID: credentialID)] = secret }
  }

  public func loadSecret(profileID: String, credentialID: String) throws -> String? {
    lock.withLock { values[key(profileID: profileID, credentialID: credentialID)] }
  }

  public func deleteSecret(profileID: String, credentialID: String) throws {
    lock.withLock { _ = values.removeValue(forKey: key(profileID: profileID, credentialID: credentialID)) }
  }
}
