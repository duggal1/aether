import SwiftUI

private struct AetherFocusedWindowKey: FocusedValueKey {
    typealias Value = BrowserWindowModel
}

extension FocusedValues {
    public var aetherWindow: BrowserWindowModel? {
        get { self[AetherFocusedWindowKey.self] }
        set { self[AetherFocusedWindowKey.self] = newValue }
    }
}

public struct BrowserCommands: Commands {
    @FocusedValue(\.aetherWindow) private var window
    @Environment(\.openWindow) private var openWindow
    public init() {}
    public var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") { window?.toggleSidebar() }
                .keyboardShortcut("b")
                .disabled(window == nil)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { window?.newTab() }.keyboardShortcut("t").disabled(window == nil)
            Button("New Private Tab") { window?.newPrivateTab() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(window == nil)
            Button("New Window") { openWindow(id: "browser") }.keyboardShortcut("n")
        }
        CommandMenu("Tabs") {
            Button("Close Tab") { if let id = window?.selectedID { window?.closeOrPutDown(id) } }
                .keyboardShortcut("w")
            Button("Reopen Closed Tab") { window?.restoreClosed() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Duplicate Tab") { if let id = window?.selectedID { window?.duplicate(id) } }
                .keyboardShortcut("d").disabled(window?.selectedID == nil)
            Button("Rename Tab…") { if let id = window?.selectedID { window?.renamingTabID = id } }
                .disabled(window?.selectedID == nil)
            Button("Sleep Tab") { if let id = window?.selectedID { window?.sleepTab(id) } }
                .disabled(window?.selectedID == nil)
            Divider()
            Button("Next Tab") { window?.switchToNext(1) }
                .keyboardShortcut(.tab, modifiers: [.control])
            Button("Previous Tab") { window?.switchToNext(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Switch Tabs…") { window?.showsTabSwitcher.toggle() }
                .keyboardShortcut("k").disabled(window == nil)
            Button("Toggle Tab Layout") { window?.toggleArrangement() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            ForEach(1...9, id: \.self) { number in
                Button("Select Tab \(number)") { window?.selectTab(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                    .disabled(window == nil)
            }
        }
        CommandMenu("Share") {
            Button("Share Page…") { window?.sharePage() }.disabled(window?.selected?.url == nil)
            Button("Copy as Markdown Link") { window?.copyMarkdownLink() }.disabled(window?.selected?.url == nil)
        }
        CommandMenu("Video") {
            Button("Float Video") { window?.toggleFloatingVideo() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(window?.selected?.enginePageID == nil)
        }
        CommandMenu("Automation") {
            Button("Local Agent Connection…") {
                guard let window,
                    let provider = window.workspace.engine as? any BrowserAutomationProviding else { return }
                Task {
                    do { window.alert = try await provider.authorizeAutomation(profileID: window.activeProfileID) }
                    catch { window.alert = error.localizedDescription }
                }
            }.disabled(window == nil)
        }
        CommandMenu("Navigation") {
            Button("Focus Address Bar") { window?.addressFocusNonce += 1 }.keyboardShortcut("l")
            Button("Reload") { window?.perform(.reload) }.keyboardShortcut("r")
            Button("Back") { window?.perform(.back) }.keyboardShortcut("[", modifiers: .command)
            Button("Forward") { window?.perform(.forward) }.keyboardShortcut("]", modifiers: .command)
            Divider()
            Button("Join Meeting") { window?.joinMeeting() }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(window?.selected?.enginePageID == nil)
            Divider()
            Button("Search Tabs, History, Bookmarks") { window?.showsTabSearch = true }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("History") { window?.showHistoryPanel() }.keyboardShortcut("y")
            Button("Bookmarks") { window?.showBookmarksPanel() }
                .keyboardShortcut("b", modifiers: [.command, .option])
            Button("Toggle Bookmarks Bar") { window?.showsBookmarksBarOverride = (window?.showsBookmarksBarOverride ?? window?.workspace.preferences.showBookmarksBar ?? false) ? false : true }
                .disabled(window == nil)
            Button("Site Information") { window?.showsSiteCard.toggle() }
                .disabled(window?.selected?.url == nil)
            Button("Inspect Page") { window?.showsInspector = true }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button("Find in Page") { window?.showsFind = true }
            Button("Reader") { window?.showsReader = true }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Zoom In") {
                guard let w = window, let host = w.selected?.url.flatMap({ URL(string: $0)?.host }) else { return }
                w.setZoom(w.zoomForHost(host) + 0.1, host: host)
            }.keyboardShortcut("+").disabled(window?.selected?.url == nil)
            Button("Zoom Out") {
                guard let w = window, let host = w.selected?.url.flatMap({ URL(string: $0)?.host }) else { return }
                w.setZoom(w.zoomForHost(host) - 0.1, host: host)
            }.keyboardShortcut("-").disabled(window?.selected?.url == nil)
            Button("Reset Zoom") {
                guard let w = window, let host = w.selected?.url.flatMap({ URL(string: $0)?.host }) else { return }
                w.setZoom(1.0, host: host)
            }.keyboardShortcut("0").disabled(window?.selected?.url == nil)
        }
        CommandMenu("Developer") {
            Button("Inspect Element") { webInspector(.toggleWebInspector) }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(webInspectorPage == nil)
            Button("Show JavaScript Console") { webInspector(.showWebConsole) }
                .keyboardShortcut("j", modifiers: [.command, .option])
                .disabled(webInspectorPage == nil)
            Button("Pick Element to Inspect") { webInspector(.pickWebElement) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(webInspectorPage == nil)
        }
    }

    private enum WebInspectorAction {
        case toggleWebInspector
        case showWebConsole
        case pickWebElement
    }

    private var webInspectorPage: (provider: any BrowserWebInspectorProviding, pageID: String)? {
        guard let window,
              let pageID = window.selected?.enginePageID,
              let provider = window.workspace.engine as? any BrowserWebInspectorProviding
        else { return nil }
        return (provider, pageID)
    }

    private func webInspector(_ action: WebInspectorAction) {
        guard let target = webInspectorPage else { return }
        Task { @MainActor in
            do {
                switch action {
                case .toggleWebInspector: try await target.provider.toggleWebInspector(pageID: target.pageID)
                case .showWebConsole: try await target.provider.showWebConsole(pageID: target.pageID)
                case .pickWebElement: try await target.provider.pickWebElement(pageID: target.pageID)
                }
            } catch {
                window?.alert = "The inspector is not available: \(error.localizedDescription)"
            }
        }
    }
}
