import Foundation
import Testing
@testable import AetherHumanUI

struct AddressResolverTests {
    @Test func validHTTPSAddress() {
        #expect(AddressResolver.resolve("https://github.com/duggal1/aether")?.host == "github.com")
    }
    @Test func bareDomain() {
        #expect(AddressResolver.resolve("github.com")?.absoluteString == "https://github.com")
    }
    @Test func searchQuery() {
        let url = AddressResolver.resolve("Swift native browser", provider: .google)
        #expect(url?.host == "www.google.com")
        #expect(url?.query?.contains("Swift") == true)
    }
    @Test func alternateSearchProvider() {
        #expect(AddressResolver.resolve("swift", provider: .duckDuckGo)?.host == "duckduckgo.com")
    }
    @Test func emptyInput() {
        #expect(AddressResolver.resolve("  ") == nil)
    }

    private func components(_ url: URL?) throws -> URLComponents {
        let resolved = try #require(url)
        return try #require(URLComponents(url: resolved, resolvingAgainstBaseURL: false))
    }

    private func value(_ url: URL?, _ name: String) throws -> String? {
        try components(url).queryItems?.first { $0.name == name }?.value
    }

    @Test func googleSearchURLShape() throws {
        let url = AddressResolver.resolve("SwiftUI Liquid Glass", provider: .google)
        #expect(url?.host == "www.google.com")
        #expect(url?.path == "/search")
        #expect(try value(url, "q") == "SwiftUI Liquid Glass")
        #expect(try value(url, "udm") == nil)
    }

    @Test func googleAIModeRouting() throws {
        let url = AddressResolver.resolve("WebKit performance", provider: .googleAI)
        #expect(url?.host == "www.google.com")
        #expect(url?.path == "/search")
        #expect(try value(url, "q") == "WebKit performance")
        #expect(try value(url, "udm") == "50")
    }

    @Test func queryEncodingIsExact() throws {
        let query = "a&b+c#d?e=f 100% ünïcode"
        let url = AddressResolver.resolve(query, provider: .google)
        #expect(try value(url, "q") == query)
        #expect(url?.absoluteString.contains("&b") == false)
        #expect(url?.absoluteString.contains("#") == false)
    }

    @Test func providerHomepages() {
        #expect(SearchProvider.googleAI.homepage.absoluteString == "https://www.google.com/ai")
        #expect(SearchProvider.google.homepage.absoluteString == "https://www.google.com/")
    }

    @Test func persistedProviderIdentitiesAreStable() {
        let stored = ["Google", "Google AI Mode", "DuckDuckGo", "Bing", "Brave"]
        #expect(Array(SearchProvider.allCases.map(\.rawValue).prefix(stored.count)) == stored)
        #expect(SearchProvider.allCases.contains(.jev))
        #expect(SearchProvider(rawValue: "Google AI Mode") == .googleAI)
        #expect(SearchProvider(rawValue: "Jev") == .jev)
    }

    @Test func jevProviderRoutesThroughIntelligenceInsteadOfAURL() {
        #expect(SearchProvider.jev.usesIntelligence)
        #expect(SearchProvider.jev.searchEndpoint == nil)
        #expect(SearchProvider.jev.searchURL(for: "apple") == nil)
        #expect(SearchProvider.google.usesIntelligence == false)
    }

    @Test func directURLClassificationStaysDeterministic() {
        #expect(AddressResolver.directURL("apple.com")?.absoluteString == "https://apple.com")
        #expect(AddressResolver.directURL("https://apple.com/x")?.host == "apple.com")
        #expect(AddressResolver.directURL("apple") == nil)
        #expect(AddressResolver.directURL("two words") == nil)
    }

    @Test func bareDomainsNavigateDirectly() {
        #expect(AddressResolver.resolve("apple.com")?.absoluteString == "https://apple.com")
        #expect(AddressResolver.resolve("https://apple.com")?.absoluteString == "https://apple.com")
        #expect(AddressResolver.resolve("http://apple.com")?.absoluteString == "http://apple.com")
    }

    @Test func pathsQueriesAndPortsArePreserved() {
        #expect(AddressResolver.resolve("youtube.com/watch?v=dQw4w9WgXcQ")?.absoluteString
            == "https://youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(AddressResolver.resolve("example.com:8080/a/b?x=1#f")?.absoluteString
            == "https://example.com:8080/a/b?x=1#f")
    }

    @Test func localAddressesNavigateDirectly() {
        #expect(AddressResolver.directURL("localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(AddressResolver.directURL("localhost:3000/api?q=1")?.absoluteString == "http://localhost:3000/api?q=1")
        #expect(AddressResolver.directURL("LOCALHOST:3000")?.absoluteString == "http://LOCALHOST:3000")
        #expect(AddressResolver.directURL("127.0.0.1:8765/")?.absoluteString == "http://127.0.0.1:8765/")
        #expect(AddressResolver.directURL("192.168.1.1")?.absoluteString == "http://192.168.1.1")
        #expect(AddressResolver.directURL("10.0.0.5:8080/status")?.absoluteString == "http://10.0.0.5:8080/status")
        #expect(AddressResolver.directURL("[::1]:3000")?.absoluteString == "http://[::1]:3000")
    }

    @Test func ordinaryTextStaysSearch() {
        #expect(AddressResolver.directURL("hi") == nil)
        #expect(AddressResolver.directURL("how fast is webkit") == nil)
        #expect(AddressResolver.directURL("v1.2") == nil)
        #expect(AddressResolver.directURL("3.14") == nil)
        #expect(AddressResolver.directURL("notaurl") == nil)
        #expect(AddressResolver.resolve("hi", provider: .google)?.host == "www.google.com")
        let question = AddressResolver.resolve("what is the fastest browser", provider: .google)
        #expect(question?.host == "www.google.com")
    }

    @Test func credentialsNeverBecomeDirectURLs() {
        #expect(AddressResolver.directURL("https://person:secret@example.com/") == nil)
        #expect(AddressResolver.directURL("user@example.com") == nil)
    }

    @Test func invalidPortsFallBackToSearch() {
        #expect(AddressResolver.directURL("example.com:abc") == nil)
    }

    @Test func suggestionIntentMatchesResolver() {
        let open = OmniboxSuggestionBuilder.intentRow(prefix: "apple.com", provider: .google)
        #expect(open.kind == .open)
        #expect(open.url == "https://apple.com")
        let local = OmniboxSuggestionBuilder.intentRow(prefix: "localhost:3000", provider: .google)
        #expect(local.kind == .open)
        #expect(local.url == "http://localhost:3000")
        let search = OmniboxSuggestionBuilder.intentRow(prefix: "v1.2", provider: .google)
        #expect(search.kind == .open)
        #expect(search.url == nil)
        #expect(search.completionText == "v1.2")
        let words = OmniboxSuggestionBuilder.intentRow(prefix: "two words", provider: .google)
        #expect(words.url == nil)
    }
}

struct OmniboxCommitTests {
    @Test func rememberedSitesBecomeDefaultNavigationAcrossDistinctHosts() {
        let profile = UUID()
        let visits = [
            BrowserVisit(profileID: profile, title: "Clay", url: "https://clay.com/pricing"),
            BrowserVisit(profileID: profile, title: "Neon", url: "https://neon.com/docs"),
            BrowserVisit(profileID: profile, title: "Clear", url: "https://clear.com/")
        ]
        for (word, expected) in [
            ("clay", "https://clay.com/"),
            ("neon", "https://neon.com/"),
            ("clear", "https://clear.com/")
        ] {
            let remembered = AddressResolver.rememberedSite(word, visits: visits, bookmarks: [])
            #expect(remembered?.absoluteString == expected)
            let intent = OmniboxSuggestionBuilder.intentRow(prefix: word, provider: .google,
                                                              rememberedSite: remembered)
            #expect(intent.url == expected)
            #expect(OmniboxSuggestionBuilder.commitTarget(draft: word, selected: intent,
                                                            rememberedSite: remembered) == expected)
        }
        #expect(AddressResolver.rememberedSite("clay tutorial", visits: visits, bookmarks: []) == nil)
        #expect(AddressResolver.rememberedSite("clay.com", visits: visits, bookmarks: []) == nil)
        #expect(AddressResolver.rememberedSite("cl", visits: visits, bookmarks: [])?.host == "clay.com")
        #expect(AddressResolver.rememberedSite("cly", visits: visits, bookmarks: [])?.host == "clay.com")
    }

    @Test func rememberedSitesSurviveArchiveReload() throws {
        let suite = "aether.site-memory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = BrowserProfile(name: "Test")
        BrowserPersistence.save(BrowserArchive(profiles: [profile],
            visits: [BrowserVisit(profileID: profile.id, title: "Clay", url: "https://clay.com/article")]),
            defaults: defaults)
        let restored = BrowserPersistence.load(defaults: defaults)
        #expect(AddressResolver.rememberedSite("clay", visits: restored.visits,
                                                bookmarks: restored.bookmarks)?.absoluteString == "https://clay.com/")
    }

    @Test func typedAddressBeatsAHoveredSearchSuggestion() {
        let search = OmniboxSuggestion(kind: .open,
                                       title: "Search Google for “apple.com”",
                                       completion: "apple.com")
        #expect(OmniboxSuggestionBuilder.commitTarget(draft: "apple.com", selected: search)
            == "https://apple.com")
    }

    @Test func typedAddressBeatsAProviderCompletion() {
        let completion = OmniboxSuggestion(kind: .completion, title: "apple.com store",
                                           completion: "apple.com store")
        #expect(OmniboxSuggestionBuilder.commitTarget(draft: "apple.com", selected: completion)
            == "https://apple.com")
    }

    @Test func deliberateLibrarySelectionIsStillHonoured() {
        let bookmark = OmniboxSuggestion(kind: .bookmark, title: "Apple",
                                         url: "https://apple.com/pie")
        #expect(OmniboxSuggestionBuilder.commitTarget(draft: "apple.com", selected: bookmark)
            == "https://apple.com/pie")
    }

    @Test func addressesWithPathsPortsAndQueriesSurviveCommit() {
        let hover = OmniboxSuggestion(kind: .completion, title: "youtube watch",
                                      completion: "youtube watch")
        #expect(OmniboxSuggestionBuilder.commitTarget(
            draft: "youtube.com/watch?v=dQw4w9WgXcQ", selected: hover)
            == "https://youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(OmniboxSuggestionBuilder.commitTarget(draft: "localhost:3000", selected: nil)
            == "http://localhost:3000")
    }
}

@MainActor
struct NavigationEntryTests {
    @Test func newTabSearchUsesOnlyTheActiveProfilesRememberedSite() throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let profile = workspace.createProfile("Site memory test")
        defer { _ = workspace.deleteProfile(profile.id) }
        let name = "memory-\(UUID().uuidString.lowercased())"
        let site = "https://\(name).example/"
        workspace.recordVisit(profileID: profile.id, title: "Remembered", url: site + "article")
        #expect(workspace.rememberedSite(for: name, profileID: workspace.defaultProfileID) == nil)
        let window = BrowserWindowModel(workspace: workspace)
        window.switchProfile(profile.id)
        window.navigateSelected(name, intelligence: true)
        #expect(window.selected?.pendingURL == site)
        workspace.clearHistory(profile.id)
        #expect(workspace.rememberedSite(for: name, profileID: profile.id) == nil)
    }

    @Test func typingResetsSuggestionSelection() throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        // Ambient seeded shortcuts also match "apple", so the row order would
        // otherwise depend on whether defaults were already persisted.
        // Ambient state from earlier runs must not influence the row order:
        // seeded shortcuts also match "apple", persisted visits shift indexes,
        // and a persisted bookmark on the same host would win the per-host
        // dedupe so the fixture row never appears at all.
        for shortcut in workspace.shortcuts { workspace.removeShortcut(shortcut.id) }
        workspace.clearHistory(window.activeProfileID)
        for mark in workspace.bookmarks(for: window.activeProfileID) {
            workspace.deleteBookmark(mark.id)
        }
        let target = "https://apple.com/pie-" + UUID().uuidString
        workspace.toggleBookmark(profileID: window.activeProfileID, title: "apple pie",
                                 url: target)
        window.suggestions.update(prefix: "apple", window: window)
        #expect(window.suggestions.rows.count >= 2)
        // Select by identity: persisted visits can also match and shift the row.
        let bookmark = try #require(
            window.suggestions.rows.firstIndex { $0.url == target },
            "rows: \(window.suggestions.rows.map { "\($0.kind.rawValue):\($0.url ?? $0.title)" })")
        #expect(bookmark > 0)
        window.suggestions.move(bookmark)
        #expect(window.suggestions.selectedRow?.url == target)
        window.suggestions.update(prefix: "apple.", window: window)
        #expect(window.suggestions.selectedRow?.id == window.suggestions.rows.first?.id)
        #expect(window.suggestions.rows.first?.url == nil)
    }

    @Test func ordinaryTextPrefersTheRowThenFallsBackToTypedText() {
        #expect(OmniboxSuggestionBuilder.commitTarget(draft: "hi", selected: nil) == nil)
        let search = OmniboxSuggestion(kind: .open, title: "Search Google for “hi”", completion: "hi")
        #expect(OmniboxSuggestionBuilder.commitTarget(draft: "hi", selected: search) == "hi")
    }

    @Test func failedNavigationKeepsRetryAddress() async throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        guard let tab = window.selected else { throw TestFailure.missingTab }
        window.navigateSelected("apple.com")
        #expect(tab.pendingURL == "https://apple.com")
        #expect(tab.url == "https://apple.com")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if case .failed = tab.loadState { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard case .failed = tab.loadState else { throw TestFailure.neverFailed }
        #expect(tab.pendingURL == "https://apple.com")
        #expect(tab.url == "https://apple.com")
    }

    enum TestFailure: Error {
        case missingTab
        case neverFailed
    }
}
