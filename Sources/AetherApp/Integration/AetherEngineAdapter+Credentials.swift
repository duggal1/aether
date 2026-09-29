import AetherHumanUI
import EngineCore
import EngineRuntime
import Foundation

extension AetherEngineAdapter: BrowserCredentialVaultProviding {
  func savedCredentials(profileID: UUID, origin: String?) async throws
    -> [BrowserCredentialSummary]
  {
    let contextID = try await context(for: profileID)
    try await migrateLegacyCredentials(profileID: profileID, contextID: contextID)
    return try await engine.runtime.listCredentials(contextID: contextID, origin: origin).map {
      BrowserCredentialSummary(
        id: $0.id, profileID: profileID, origin: $0.origin,
        username: $0.username, label: $0.label)
    }
  }

  func saveCredential(
    profileID: UUID, origin: String, username: String, password: String
  ) async throws {
    let contextID = try await context(for: profileID)
    try await migrateLegacyCredentials(profileID: profileID, contextID: contextID)
    _ = try await engine.runtime.saveCredential(
      contextID: contextID, origin: origin, username: username, password: password)
  }

  func deleteCredential(profileID: UUID, credentialID: String) async throws {
    let contextID = try await context(for: profileID)
    try await migrateLegacyCredentials(profileID: profileID, contextID: contextID)
    guard try await engine.runtime.deleteCredential(
      contextID: contextID, credentialID: credentialID)
    else { throw CredentialVaultError.notFound }
  }

  func fillCredential(pageID: String, credentialID: String, fillUsername: Bool) async throws {
    try await engine.runtime.fillCredential(
      pageID: page(pageID), credentialID: credentialID, fillUsername: fillUsername)
  }

  /// The engine only hands a secret back for a credential its own profile
  /// holds, so a credential id from another profile reads as not found.
  func savedPassword(profileID: UUID, credentialID: String) async throws -> String {
    let contextID = try await context(for: profileID)
    return try await engine.runtime.credentialSecret(
      contextID: contextID, credentialID: credentialID).password
  }

  private func migrateLegacyCredentials(profileID: UUID, contextID: ContextID) async throws {
    guard !migratedCredentialProfiles.contains(profileID) else { return }
    var allSecretsAvailable = true
    for item in AetherCredentialVault.saved(profileID: profileID) {
      guard let legacy = AetherCredentialVault.credentials(
        profileID: profileID, origin: item.origin).first(where: { $0.username == item.username })
      else {
        allSecretsAvailable = false
        continue
      }
      _ = try await engine.runtime.saveCredential(
        contextID: contextID, origin: item.origin, username: item.username,
        password: legacy.password)
      guard AetherCredentialVault.delete(item) else {
        throw CredentialVaultError.store("Legacy Keychain credential could not be removed.")
      }
    }
    if allSecretsAvailable { migratedCredentialProfiles.insert(profileID) }
  }
}
