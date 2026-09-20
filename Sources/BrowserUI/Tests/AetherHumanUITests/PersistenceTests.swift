import Foundation
import Testing
@testable import AetherHumanUI

struct PersistenceTests {
    @Test func roundTripProfileAndBookmark() {
        let suite = "aether.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { Issue.record("Unable to create test defaults"); return }
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = BrowserProfile(name: "Testing")
        let archive = BrowserArchive(profiles: [profile], bookmarks: [
            BrowserBookmark(profileID: profile.id, title: "Aether", url: "https://example.com")
        ], defaultProfileID: profile.id)
        BrowserPersistence.save(archive, defaults: defaults)
        let loaded = BrowserPersistence.load(defaults: defaults)
        #expect(loaded.profiles.count == 1)
        #expect(loaded.profiles.first?.id == profile.id)
        #expect(loaded.bookmarks.first?.profileID == profile.id)
    }
}
