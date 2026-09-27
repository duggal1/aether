import Foundation
import Testing
@testable import AetherHumanUI

// Aggressive tests for Search-ported features.
struct SearchPortEngineTests {
    @Test func ecosiaStartpageKagiResolve() throws {
        let e = AddressResolver.resolve("cats", provider: .ecosia)
        #expect(e?.host == "www.ecosia.org")
        #expect(try URLComponents(url: e!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value == "cats")
        let s = AddressResolver.resolve("cats", provider: .startpage)
        #expect(s?.host == "www.startpage.com")
        #expect(s?.path == "/sp/search")
        let k = AddressResolver.resolve("cats", provider: .kagi)
        #expect(k?.host == "kagi.com")
    }
    @Test func customTemplateRequiresHostAndPlaceholder() {
        #expect(SearchProvider.acceptsTemplate("https://example.com/search?q=%s"))
        #expect(!SearchProvider.acceptsTemplate("https://example.com/search?q="))
        #expect(!SearchProvider.acceptsTemplate("not a url %s"))
        #expect(!SearchProvider.acceptsTemplate("ftp://example.com/?q=%s"))
        let url = SearchProvider.url(for: "a&b c", template: "https://example.com/search?q=%s")
        #expect(url?.absoluteString == "https://example.com/search?q=a%26b%20c")
    }
    @Test func customProviderFallsBackToGoogleOnBadTemplate() {
        let bad = AddressResolver.resolve("hello", provider: .custom, customTemplate: "bad template")
        #expect(bad?.host == "www.google.com")
        let good = AddressResolver.resolve("hello", provider: .custom, customTemplate: "https://example.com/s?q=%s")
        #expect(good?.host == "example.com")
    }
    @Test func startpageUsesQueryParam() throws {
        let url = try #require(AddressResolver.resolve("hello world", provider: .startpage))
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.queryItems?.first(where: { $0.name == "query" })?.value == "hello world")
        #expect(comps.queryItems?.first(where: { $0.name == "q" }) == nil)
    }
}

struct SearchPortBookmarkHTMLTests {
    @Test func netscapeHTMLImportParsesAnchors() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
        <DT><A HREF="https://example.com/a" ADD_DATE="1">Example A</A>
        <DT><A HREF="https://example.org/b">B</A>
        <DT><A HREF="javascript:void(0)">Nope</A>
        </DL><p>
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("bookmarks.html")
        try html.write(to: file, atomically: true, encoding: .utf8)
        let items = try BookmarkTransfer.importNetscapeHTML(file)
        #expect(items.count == 2)
        #expect(items[0].url == "https://example.com/a")
        #expect(items[0].title == "Example A")
        #expect(items[1].folder == "Imported")
    }
}

@MainActor
struct SearchPortVeilTests {
    @Test func veilCSSIsolatesSelectors() {
        let store = VeilStore.shared
        let host = "veil-test-\(UUID().uuidString).example"
        #expect(store.css(on: host).isEmpty)
        store.hide(".cookie-banner", label: ".cookie-banner", note: "", on: host)
        store.hide("#overlay", label: "#overlay", note: "", on: host)
        let css = store.css(on: host)
        #expect(css.contains(".cookie-banner { display: none !important; }"))
        #expect(css.contains("#overlay { display: none !important; }"))
        // Spared selector left out for hover-preview.
        #expect(!store.css(on: host, without: ".cookie-banner").contains(".cookie-banner"))
        #expect(store.css(on: "other.example").isEmpty)
        store.restoreAll(on: host)
        #expect(store.css(on: host).isEmpty)
    }
    @Test func veilHostStripsWWW() {
        #expect(VeilStore.shared.host(of: URL(string: "https://www.example.com/x")) == "example.com")
        #expect(VeilStore.shared.host(of: "https://example.com/x") == "example.com")
        #expect(VeilStore.shared.host(of: "not a url") == nil)
    }
}

@MainActor
struct SearchPortTabTests {
    @Test func renameSurvivesSessionRoundTrip() throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        guard let tab = window.selected else { throw TabFailure.noTab }
        window.renameTab(tab.id, to: "  My Research  ")
        #expect(tab.customTitle == "My Research")
        #expect(tab.displayTitle == "My Research")
        let saved = try #require(BrowserSessionTab(tab: tab))
        #expect(saved.customTitle == "My Research")
        let restored = BrowserTab(id: saved.id, profileID: saved.profileID, title: saved.title, url: saved.url)
        restored.customTitle = saved.customTitle
        #expect(restored.displayTitle == "My Research")
    }
    @Test func openBesideInsertsAfterSelected() throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        _ = window.newTab(url: "https://example.com/a")
        _ = window.newTab(url: "https://example.com/b")
        guard let first = window.tabs.first else { throw TabFailure.noTab }
        window.select(first.id)
        let beside = window.openBeside(url: "https://example.com/beside", select: false)
        #expect(window.tabs[1].id == beside.id)
        #expect(window.selectedID == first.id)
    }
    @Test func privateTabNeverSerializes() throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        let priv = window.newPrivateTab(url: "https://example.com/secret")
        #expect(priv.isPrivateTab)
        #expect(BrowserSessionTab(tab: priv) == nil)
    }
    @Test func pinnedPutDownInsteadOfClose() throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        guard let tab = window.selected else { throw TabFailure.noTab }
        window.togglePin(tab.id)
        #expect(tab.isPinned)
        window.closeOrPutDown(tab.id)
        #expect(!tab.isPinned)
        #expect(window.tabs.contains(where: { $0.id == tab.id }))
    }
    @Test func sleepReleasesPageAndWakesOnSelect() throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        let a = window.newTab(url: "https://example.com/a")
        let b = window.newTab(url: "https://example.com/b")
        // Simulate built pages without a real engine.
        a.enginePageID = "page-a"
        b.enginePageID = "page-b"
        window.select(a.id)
        window.sleepTab(b.id)
        #expect(b.isSleeping)
        #expect(b.enginePageID == nil)
        #expect(b.needsRestoreLoad)
        window.select(b.id)
        #expect(!b.isSleeping)
    }
    @Test func perSiteZoomPersistsAndResetsAtOne() throws {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        #expect(window.zoomForHost("example.com") == 1.0)
        window.setZoom(1.5, host: "Example.COM")
        #expect(window.zoomForHost("example.com") == 1.5)
        window.setZoom(1.0, host: "example.com")
        #expect(window.zoomForHost("example.com") == 1.0)
        window.setZoom(10, host: "example.com")
        #expect(window.zoomForHost("example.com") == 3.0)
    }
    enum TabFailure: Error { case noTab }
}

struct SearchPortPersistenceTests {
    @Test func quarantineKeepsRawPayload() throws {
        let suite = "aether.quarantine.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "aether.human.session.v1")
        let session = BrowserPersistence.loadSession(defaults: defaults)
        #expect(session.windows.isEmpty)
        #expect(defaults.dictionaryRepresentation().keys.contains(where: { $0.hasPrefix("aether.quarantine.session.") }))
    }
}
