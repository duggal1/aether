import AetherHumanUI
import Foundation

extension AetherEngineAdapter: BrowserLibraryProviding {
  func loadLibrary(profileID: UUID) async throws -> BrowserProfileLibrary? {
    let context = try await context(for: profileID)
    let data = try await engine.runtime.checkpointValue(contextID: context, key: "human.library.v1")
    var library = try data.map { try JSONDecoder().decode(BrowserProfileLibrary.self, from: $0) }
    let actual = try await engine.runtime.listBookmarks(contextID: context)
    if !actual.isEmpty || library != nil {
      var bookmarks: [BrowserBookmark] = []
      for mark in actual {
        var value = library?.bookmarks.first { $0.url == mark.url }
          ?? BrowserBookmark(profileID: profileID, title: mark.title, url: mark.url)
        value.title = mark.title
        value.createdAt = Date(timeIntervalSince1970: mark.createdAt)
        bookmarks.append(value)
      }
      library = BrowserProfileLibrary(bookmarks: bookmarks, visits: library?.visits ?? [])
    }
    return library
  }

  func saveLibrary(profileID: UUID, library: BrowserProfileLibrary) async throws {
    let context = try await context(for: profileID)
    let existing = try await engine.runtime.listBookmarks(contextID: context)
    let desired = library.bookmarks.filter { $0.profileID == profileID }
    let existingByURL = Dictionary(uniqueKeysWithValues: existing.map { ($0.url, $0) })
    let desiredByURL = Dictionary(uniqueKeysWithValues: desired.map { ($0.url, $0) })
    var bookmarksChanged = false
    for item in existing where desiredByURL[item.url] == nil {
      if let url = URL(string: item.url) { _ = try await engine.runtime.removeBookmark(contextID: context, url: url) }
      bookmarksChanged = true
    }
    for item in desired {
      guard let url = URL(string: item.url) else { continue }
      if let current = existingByURL[item.url], current.title == item.title { continue }
      _ = try await engine.runtime.addBookmark(contextID: context, url: url, title: item.title)
      bookmarksChanged = true
    }
    let data = try JSONEncoder().encode(library)
    let previous = try await engine.runtime.checkpointValue(contextID: context, key: "human.library.v1")
    if previous != data {
      try await engine.runtime.setCheckpoint(contextID: context, key: "human.library.v1", value: data)
    }
    if bookmarksChanged {
      try await engine.runtime.checkpoint(contextID: context)
    }
  }
}
