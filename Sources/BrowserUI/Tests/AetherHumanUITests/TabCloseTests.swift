import Foundation
import Testing
@testable import AetherHumanUI

/// Closing tabs is one change to the window, however many tabs it takes down.
///
/// These pin what the single-tab path used to get for free and the batch path
/// had to keep when it took over: which tab is left selected, what "close
/// others" means, and that emptying a window leaves exactly one tab — a tab,
/// never two, however the last one went.
@MainActor
struct TabCloseTests {
    private func makeWindow(tabs count: Int) -> BrowserWindowModel {
        let workspace = BrowserWorkspace(engine: DisconnectedEnginePort())
        let window = BrowserWindowModel(workspace: workspace)
        while window.tabs.count < count { _ = window.newTab() }
        return window
    }

    @Test func batchCloseRemovesExactlyThoseTabs() {
        let window = makeWindow(tabs: 12)
        let doomed = window.tabs.enumerated().filter { $0.offset % 3 == 0 }.map { $0.element.id }
        let survivors = window.tabs.filter { !doomed.contains($0.id) }.map(\.id)
        window.close(ids: doomed)
        #expect(window.tabs.map(\.id) == survivors)
    }

    @Test func batchCloseOfNothingChangesNothing() {
        let window = makeWindow(tabs: 4)
        let before = window.tabs.map(\.id)
        window.close(ids: [])
        #expect(window.tabs.map(\.id) == before)
    }

    @Test func closingEveryTabLeavesOneFreshTab() {
        let window = makeWindow(tabs: 7)
        window.close(ids: window.tabs.map(\.id))
        #expect(window.tabs.count == 1)
        #expect(window.tabs.first?.loadState == .newTab)
        #expect(window.selectedID == window.tabs.first?.id)
    }

    @Test func closingEveryTabOneAtATimeAlsoLeavesOne() {
        let window = makeWindow(tabs: 9)
        for id in window.tabs.map(\.id) { window.close(id) }
        #expect(window.tabs.count == 1)
    }

    @Test func closingASelectedTabSelectsTheOneThatTookItsPlace() {
        let window = makeWindow(tabs: 5)
        let ids = window.tabs.map(\.id)
        window.select(ids[2])
        window.close(ids[2])
        #expect(window.selectedID == ids[3])
    }

    @Test func closingASelectedLastTabSelectsTheNewLast() {
        let window = makeWindow(tabs: 4)
        let ids = window.tabs.map(\.id)
        window.select(ids[3])
        window.close(ids[3])
        #expect(window.selectedID == ids[2])
    }

    @Test func closingUnselectedTabsLeavesTheSelectionAlone() {
        let window = makeWindow(tabs: 6)
        let ids = window.tabs.map(\.id)
        window.select(ids[1])
        window.close(ids: [ids[3], ids[4]])
        #expect(window.selectedID == ids[1])
    }

    @Test func closingATabThatIsNotThereIsIgnored() {
        let window = makeWindow(tabs: 3)
        let before = window.tabs.map(\.id)
        let selected = window.selectedID
        window.close(UUID())
        #expect(window.tabs.map(\.id) == before)
        #expect(window.selectedID == selected)
    }

    @Test func closeOthersKeepsTheTabAndThePinnedOnes() {
        let window = makeWindow(tabs: 6)
        let ids = window.tabs.map(\.id)
        window.togglePin(ids[4])
        window.closeOthers(ids[1])
        #expect(window.tabs.map(\.id) == [ids[1], ids[4]])
    }

    @Test func closeOrPutDownUnpinsFirstThenCloses() {
        let window = makeWindow(tabs: 3)
        let id = window.tabs[0].id
        window.togglePin(id)
        window.closeOrPutDown(id)
        #expect(window.tabs.contains { $0.id == id })
        #expect(window.tabs.first { $0.id == id }?.isPinned == false)
        window.closeOrPutDown(id)
        #expect(!window.tabs.contains { $0.id == id })
    }
}
