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
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { window?.newTab() }.keyboardShortcut("t").disabled(window == nil)
            Button("New Window") { openWindow(id: "browser") }.keyboardShortcut("n")
        }
        CommandMenu("Tabs") {
            Button("Close Tab") { if let id = window?.selectedID { window?.close(id) } }
                .keyboardShortcut("w")
            Button("Reopen Closed Tab") { window?.restoreClosed() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("Next Tab") { window?.switchToNext(1) }
                .keyboardShortcut(.tab, modifiers: [.control])
            Button("Previous Tab") { window?.switchToNext(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Toggle Tab Layout") { window?.toggleArrangement() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }
        CommandMenu("Automation") {
            Button("Allow Local Agents in This Profile…") {
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
            Button("History") { window?.showsHistory = true }.keyboardShortcut("y")
            Button("Bookmarks") { window?.showsBookmarks = true }
                .keyboardShortcut("b", modifiers: [.command, .option])
            Button("Inspect Page") { window?.showsInspector = true }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button("Find in Page") { window?.showsFind = true }.keyboardShortcut("f")
            Button("Reader") { window?.showsReader = true }
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }
}
