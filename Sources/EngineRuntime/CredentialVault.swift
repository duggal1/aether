import EngineCore
import Foundation
import Persistence

/// Agent-readable credential metadata. Carries NO secret material —
/// `credentials.list` returns exactly this shape.
public struct CredentialInfo: Hashable, Sendable, Codable {
  public var id: String
  public var profileID: String
  public var origin: String
  public var username: String
  public var label: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: String, profileID: String, origin: String, username: String, label: String,
    createdAt: Date, updatedAt: Date
  ) {
    self.id = id
    self.profileID = profileID
    self.origin = origin
    self.username = username
    self.label = label
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  init(_ record: CredentialRecord) {
    id = record.id
    profileID = record.profileID
    origin = record.origin
    username = record.username
    label = record.label
    createdAt = record.createdAt
    updatedAt = record.updatedAt
  }
}

public enum CredentialVaultError: Error, Sendable, CustomStringConvertible {
  case profileNotConfigured
  case invalidOrigin(String)
  case insecureScheme(String)
  case invalidUsername
  case invalidPassword
  case invalidLabel
  case notFound
  case originMismatch
  case store(String)

  public var description: String {
    switch self {
    case .profileNotConfigured: return "No profile is open for this context."
    case .invalidOrigin(let value): return "Not a usable credential origin: \(value)"
    case .insecureScheme(let value):
      return "Refusing to store a credential for non-local http origin: \(value)"
    case .invalidUsername: return "Username must be 1–256 characters."
    case .invalidPassword: return "Password must be 1–4096 characters."
    case .invalidLabel: return "Label must be at most 128 characters."
    case .notFound: return "No such credential in this profile."
    case .originMismatch: return "Credential origin does not match the page origin."
    case .store(let value): return "Credential store failed: \(value)"
    }
  }
}

extension BrowserRuntime {
  // MARK: - Agent-readable credential vault

  /// Normalizes `scheme://host[:port]`. Mirrors `AetherCredentialVault.origin`
  /// so the human save path and the agent path address the same origins.
  static func credentialOrigin(_ raw: String) -> String? {
    guard let url = URL(string: raw),
      let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
      let host = url.host?.lowercased(), !host.isEmpty, url.user == nil
    else { return nil }
    var components = URLComponents()
    components.scheme = scheme
    // URLComponents will not re-add IPv6 brackets on its own; without them
    // `.string` returns nil and loopback-literal origins become unusable.
    components.host = host.contains(":") ? "[\(host)]" : host
    if let port = url.port, !(scheme == "https" && port == 443),
      !(scheme == "http" && port == 80)
    {
      components.port = port
    }
    return components.string
  }

  private static func isLoopback(host: String) -> Bool {
    host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
  }

  private func credentialProfile(for contextID: ContextID) throws -> (store: ProfileStore, id: String) {
    guard let record = contexts[contextID], let store = record.profile else {
      throw CredentialVaultError.profileNotConfigured
    }
    let profileID = webProfileIdentifiers[contextID]?.uuidString ?? record.name
    return (store, profileID)
  }

  /// Explicit save (human confirmation dialog or authorized agent call — never
  /// silent harvesting). Upserts on `(origin, username)`: same id, new secret,
  /// refreshed `updatedAt`.
  @discardableResult
  public func saveCredential(
    contextID: ContextID, origin rawOrigin: String, username rawUsername: String,
    password: String, label rawLabel: String = ""
  ) async throws -> CredentialInfo {
    let (store, profileID) = try credentialProfile(for: contextID)
    guard let origin = Self.credentialOrigin(rawOrigin) else {
      throw CredentialVaultError.invalidOrigin(rawOrigin)
    }
    guard let scheme = URL(string: origin)?.scheme?.lowercased() else {
      throw CredentialVaultError.invalidOrigin(rawOrigin)
    }
    if scheme == "http" {
      let host = URL(string: origin)?.host?.lowercased() ?? ""
      guard Self.isLoopback(host: host) else {
        throw CredentialVaultError.insecureScheme(origin)
      }
    }
    let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !username.isEmpty, username.count <= 256 else { throw CredentialVaultError.invalidUsername }
    guard !password.isEmpty, password.count <= 4096 else { throw CredentialVaultError.invalidPassword }
    let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard label.count <= 128 else { throw CredentialVaultError.invalidLabel }

    let now = Date()
    let existing = (try? store.loadCredentials(origin: origin))?.first {
      $0.username == username && $0.profileID == profileID
    }
    let record = CredentialRecord(
      id: existing?.id ?? UUID().uuidString, profileID: profileID, origin: origin,
      username: username, label: label.isEmpty ? (existing?.label ?? "") : label,
      createdAt: existing?.createdAt ?? now, updatedAt: now)
    do {
      try credentialSecrets.saveSecret(password, profileID: profileID, credentialID: record.id)
      try store.saveCredential(record)
    } catch let error as CredentialVaultError { throw error }
    catch { throw CredentialVaultError.store(String(describing: error)) }
    return CredentialInfo(record)
  }

  /// Metadata only. Secrets are never included — see `credentialSecret`.
  public func listCredentials(contextID: ContextID, origin rawOrigin: String? = nil) throws
    -> [CredentialInfo]
  {
    let (store, profileID) = try credentialProfile(for: contextID)
    let records: [CredentialRecord]
    if let raw = rawOrigin, !raw.isEmpty {
      guard let origin = Self.credentialOrigin(raw) else {
        throw CredentialVaultError.invalidOrigin(raw)
      }
      records = (try? store.loadCredentials(origin: origin)) ?? []
    } else {
      records = (try? store.loadCredentials()) ?? []
    }
    return
      records
      .filter { $0.profileID == profileID }
      .map(CredentialInfo.init)
      .sorted {
        if $0.origin != $1.origin { return $0.origin < $1.origin }
        return $0.username < $1.username
      }
  }

  /// Explicit secret retrieval. The ONLY path that returns a password, and it
  /// returns exactly one, for a credentialID owned by this context's profile.
  public func credentialSecret(contextID: ContextID, credentialID: String) async throws -> (
    username: String, password: String
  ) {
    let (store, profileID) = try credentialProfile(for: contextID)
    guard let record = try? store.loadCredential(id: credentialID),
      record.profileID == profileID
    else { throw CredentialVaultError.notFound }
    guard let secret = try? credentialSecrets.loadSecret(
      profileID: profileID, credentialID: credentialID)
    else { throw CredentialVaultError.notFound }
    return (record.username, secret)
  }

  @discardableResult
  public func deleteCredential(contextID: ContextID, credentialID: String) async throws -> Bool {
    let (store, profileID) = try credentialProfile(for: contextID)
    guard let record = try? store.loadCredential(id: credentialID),
      record.profileID == profileID
    else { throw CredentialVaultError.notFound }
    do {
      try credentialSecrets.deleteSecret(profileID: profileID, credentialID: credentialID)
      return try store.deleteCredential(id: credentialID)
    } catch {
      throw CredentialVaultError.store(String(describing: error))
    }
  }

  /// Fills the page's generic login form with a stored credential. Origin-bound:
  /// the credential's origin must equal the page's current origin. Reuses the
  /// page's own `__aetherCredentialForms.fill` (same primitive as the human
  /// popover), so no per-site logic lives here.
  public func fillCredential(
    pageID: PageID, credentialID: String, fillUsername: Bool = true
  ) async throws {
    let owner = try pageOwner(pageID)
    let info = try pageInfo(pageID)
    let (store, profileID) = try credentialProfile(for: owner)
    guard let record = try? store.loadCredential(id: credentialID),
      record.profileID == profileID
    else { throw CredentialVaultError.notFound }
    guard let pageURL = info.url,
      let pageOrigin = Self.credentialOrigin(pageURL.absoluteString),
      pageOrigin == record.origin
    else { throw CredentialVaultError.originMismatch }
    guard let secret = try? credentialSecrets.loadSecret(
      profileID: profileID, credentialID: credentialID)
    else { throw CredentialVaultError.notFound }
    // WebKit pages get the isolated-world fill primitive; anything else falls
    // back to generic evaluation (which the experimental engine understands).
    if let web = webPages[pageID] {
      if let target = try await web.credentialInteractionTarget() {
        let luminance = await web.sampleLuminance(at: target) ?? target.luminance
        let point = Point(x: target.x, y: target.y)
        let viewport = Size(width: target.viewportWidth, height: target.viewportHeight)
        if target.didScroll { publishAgentInteraction(pageID: pageID, kind: .scrolling) }
        let duration = publishAgentInteraction(pageID: pageID, kind: .move, point: point,
          viewport: viewport, targetLuminance: luminance)
        try await Task.sleep(for: .seconds(max(1.0 / 60.0, duration)))
        _ = await web.moveNativePointer(to: target)
        publishAgentInteraction(pageID: pageID, kind: .typing, point: point,
          viewport: viewport, targetLuminance: luminance)
      }
      try await web.fillCredentials(
        username: record.username, password: secret, fillUsername: fillUsername)
    } else {
      let user = jsonString(record.username) ?? "\"\""
      let pass = jsonString(secret) ?? "\"\""
      _ = try await evaluate(
        pageID: pageID,
        source: "window.__aetherCredentialForms?.fill(\(fillUsername), true, \(user), \(pass))")
    }
  }

  private func pageOwner(_ pageID: PageID) throws -> ContextID {
    guard let contextID = pageOwner[pageID] else {
      throw BrowserRuntimeError.pageNotFound(pageID)
    }
    return contextID
  }

  private func jsonString(_ value: String) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
