import Foundation
import Testing
@testable import AetherHumanUI

@MainActor
struct WorkspaceTests {
    @Test func profilesIsolateShellBookmarks() {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let a = workspace.createProfile("Personal QA")
        let b = workspace.createProfile("Work QA")
        workspace.toggleBookmark(profileID: a.id, title: "A", url: "https://a.example")
        #expect(workspace.bookmarks(for: a.id).count == 1)
        #expect(workspace.bookmarks(for: b.id).isEmpty)
        _ = workspace.deleteProfile(a.id)
        #expect(workspace.bookmarks(for: a.id).isEmpty)
        _ = workspace.deleteProfile(b.id)
    }

    @Test func layoutDoesNotReplaceTabs() {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        let before = window.selectedID
        window.setArrangement(.sidebar)
        #expect(window.selectedID == before)
        window.setArrangement(.top)
        #expect(window.selectedID == before)
    }

    @Test func navigationURLMatchingToleratesCanonicalForms() {
        #expect(BrowserWindowModel.sameNavigationURL("https://github.com", "https://github.com/"))
        #expect(BrowserWindowModel.sameNavigationURL("https://github.com/", "https://github.com"))
        #expect(BrowserWindowModel.sameNavigationURL("HTTPS://GitHub.COM/pricing", "https://github.com/pricing"))
        #expect(!BrowserWindowModel.sameNavigationURL("https://github.com", "https://github.com/pricing"))
        #expect(!BrowserWindowModel.sameNavigationURL("https://github.com", "https://gitlab.com/"))
        #expect(!BrowserWindowModel.sameNavigationURL("https://github.com", nil))
    }
}
