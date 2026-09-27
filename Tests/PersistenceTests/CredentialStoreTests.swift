import Foundation
import Persistence
import Testing

private func freshCredentialDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@Test func credentialMetadataRoundTrips() throws {
  let store = try ProfileStore.open(directory: freshCredentialDirectory())
  defer { store.close() }
  let record = CredentialRecord(
    profileID: "profile-a", origin: "https://example.com", username: "user@example.com",
    label: "Personal")
  try store.saveCredential(record)
  let loaded = try store.loadCredentials(origin: "https://example.com")
  #expect(loaded.count == 1)
  #expect(loaded[0].id == record.id)
  #expect(loaded[0].profileID == "profile-a")
  #expect(loaded[0].username == "user@example.com")
  #expect(loaded[0].label == "Personal")
  // Date stores seconds since 2001 internally, so a now-Date loses
  // sub-microsecond bits across the epoch round-trip. Compare loosely.
  #expect(abs(loaded[0].createdAt.timeIntervalSince(record.createdAt)) < 0.001)
}

@Test func credentialUpsertKeepsIDAndRefreshesTimestamp() throws {
  let store = try ProfileStore.open(directory: freshCredentialDirectory())
  defer { store.close() }
  let first = CredentialRecord(
    profileID: "p", origin: "https://example.com", username: "u", label: "old")
  try store.saveCredential(first)
  let updated = CredentialRecord(
    id: first.id, profileID: "p", origin: "https://example.com", username: "u",
    label: "new", createdAt: first.createdAt, updatedAt: Date().addingTimeInterval(60))
  try store.saveCredential(updated)
  let loaded = try #require(try store.loadCredential(id: first.id))
  #expect(loaded.label == "new")
  #expect(abs(loaded.createdAt.timeIntervalSince(first.createdAt)) < 0.001)
  #expect(loaded.updatedAt > first.updatedAt)
  #expect(try store.loadCredentials().count == 1)
}

@Test func credentialDeleteRemovesRecord() throws {
  let store = try ProfileStore.open(directory: freshCredentialDirectory())
  defer { store.close() }
  let record = CredentialRecord(profileID: "p", origin: "https://example.com", username: "u")
  try store.saveCredential(record)
  #expect(try store.deleteCredential(id: record.id))
  #expect(try store.loadCredential(id: record.id) == nil)
  #expect(!(try store.deleteCredential(id: record.id)))
}

@Test func credentialTableHoldsNoSecrets() throws {
  // The table must never gain a password/secret column: secrets live in the
  // Keychain, SQLite holds lookup metadata only.
  let directory = try freshCredentialDirectory()
  let store = try ProfileStore.open(directory: directory)
  try store.saveCredential(
    CredentialRecord(profileID: "p", origin: "https://example.com", username: "u"))
  store.close()
  let db = try SQLiteStore(path: directory.appendingPathComponent("state.sqlite").path)
  defer { db.close() }
  let columns = try db.query("PRAGMA table_info(credentials);").compactMap { row -> String? in
    guard row.count > 1, case .text(let name) = row[1] else { return nil }
    return name.lowercased()
  }
  #expect(!columns.isEmpty)
  for forbidden in ["password", "secret", "pass", "passwd"] {
    #expect(!columns.contains(where: { $0.contains(forbidden) }), "forbidden column: \(columns)")
  }
  let raw = try db.query("SELECT * FROM credentials;")
  #expect(raw.count == 1)
  let dump = "\(raw)"
  #expect(!dump.contains("s3cr3t"))
}

@Test func credentialMetadataSurvivesReopen() throws {
  let directory = try freshCredentialDirectory()
  let first = try ProfileStore.open(directory: directory)
  let record = CredentialRecord(
    profileID: "profile-a", origin: "https://example.com", username: "u", label: "L")
  try first.saveCredential(record)
  first.close()
  let second = try ProfileStore.open(directory: directory)
  defer { second.close() }
  #expect(ProfileStore.schemaVersion == 4)
  let loaded = try #require(try second.loadCredential(id: record.id))
  #expect(loaded.username == "u")
  #expect(loaded.label == "L")
}
