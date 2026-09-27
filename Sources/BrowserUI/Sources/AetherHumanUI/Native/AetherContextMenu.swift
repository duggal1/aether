import AppKit
import EngineRuntime
import Foundation
import WebKit

/// The browser's own right-click menu for a page.
///
/// WebKit's menu is Safari's, and the two items in it that look most useful here
/// are the two with no public hook: "Download Image" never reaches a download
/// delegate, and "Copy Image" writes a pasteboard promise a paste does not
/// always resolve. On a plain page area it offers little more than Reload,
/// which is what a right-click in the middle of a page used to show.
///
/// So the menu is replaced rather than patched. The facts about what was
/// clicked come from `AetherPageContext`, read out of WebKit's own menu before
/// it is drawn; everything else is this browser's, drawn with system symbols and
/// following the page's own tone so the card is light over a light site and dark
/// over a dark one.
@MainActor
enum AetherContextMenu {
    static func fill(_ menu: NSMenu, context: AetherPageContext, window: BrowserWindowModel,
                     webView: WKWebView, searchItem: NSMenuItem?) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        // The card is always the dark blurred one, never Apple's native menu
        // and never the page's tone: a right-click over a light site gets the
        // same dark card as over a dark one, so the menu reads as the
        // browser's own surface wherever it opens.
        menu.appearance = NSAppearance(named: .darkAqua)

        let tab = window.selected
        let pageID = tab?.enginePageID

        if let link = context.linkURL, let url = URL(string: link) {
            add(menu, "Open Link in New Tab", symbol: "plus.rectangle.on.rectangle") {
                _ = window.newTab(url: url.absoluteString)
            }
            add(menu, "Copy Link", symbol: "link") { copy(link) }
        }

        if let image = context.imageURL, let url = URL(string: image) {
            add(menu, "Open Image in New Tab", symbol: "photo.on.rectangle") {
                _ = window.newTab(url: image)
            }
            add(menu, "Save Image…", symbol: "square.and.arrow.down") {
                AetherImageSaver.save(url)
            }
            add(menu, "Copy Image Address", symbol: "link") { copy(image) }
        }

        if context.linkURL != nil || context.imageURL != nil { menu.addItem(.separator()) }

        if let searchItem {
            menu.addItem(searchItem)
            menu.addItem(.separator())
        }

        add(menu, "Back", symbol: "chevron.backward", enabled: context.canGoBack) {
            window.perform(.back)
        }
        add(menu, "Forward", symbol: "chevron.forward", enabled: context.canGoForward) {
            window.perform(.forward)
        }
        add(menu, "Reload", symbol: "arrow.clockwise") { window.perform(.reload) }

        if let pageURL = context.pageURL {
            menu.addItem(.separator())
            add(menu, "Copy Page Address", symbol: "doc.on.doc") { copy(pageURL) }
            add(menu, "Copy as Markdown Link", symbol: "doc.richtext") {
                window.copyMarkdownLink()
            }
            add(menu, "Share…", symbol: "square.and.arrow.up") { window.sharePage() }
        }

        // The capture actions. Both act on the page that is open, not on a
        // re-opened copy of its address: the capture pipeline elsewhere starts a
        // fresh context, which has no cookies and photographs the signed-out
        // version of a signed-in page.
        if pageID != nil {
            menu.addItem(.separator())
            add(menu, "Take Screenshot", symbol: "camera") {
                capture(window: window, pageID: pageID, forAgents: false)
            }
            add(menu, "Take Screenshot for Agents", symbol: "camera.viewfinder") {
                capture(window: window, pageID: pageID, forAgents: true)
            }
            add(menu, "Copy HTML", symbol: "chevron.left.forwardslash.chevron.right") {
                copyHTML(window: window, pageID: pageID, forAgents: false)
            }
            add(menu, "Copy HTML for Agents", symbol: "curlybraces.square") {
                copyHTML(window: window, pageID: pageID, forAgents: true)
            }
        }

        // Jev reads the page, it does not write it: these ask the intelligence
        // layer to judge the page's own subject, which is what it can do. No
        // entry claims to summarise anything, because Jev does not generate text.
        if let tab, !tab.title.isEmpty, pageID != nil {
            menu.addItem(.separator())
            add(menu, "Ask Jev About This Page", symbol: "sparkles") {
                window.startJevSearch(tab, query: tab.title)
            }
        }

        // What Jev judged about this page, from the same values the chip and the
        // signals panel read — so a right-click is another way into one set of
        // claims rather than a second, separate set.
        let verdict = JevPageVerdict(signals: tab?.semanticSignals, window: window)
        if !verdict.isEmpty {
            menu.addItem(.separator())
            add(menu, "What Jev Sees (\(verdict.rows.count))", symbol: "sparkles") {
                window.showsJevSignals = true
            }
            if verdict.rows.contains(where: { $0.id == "session-expired" }) {
                add(menu, "Reload and Sign In Again", symbol: "arrow.clockwise") {
                    window.perform(.reload)
                }
            }
            if verdict.rows.contains(where: { $0.id == "related" }),
               let related = tab?.semanticSignals?.relatedPageID,
               let other = window.tabs.first(where: { $0.enginePageID == related && $0.id != tab?.id }) {
                add(menu, "Switch to “\(other.title)”", symbol: "link") {
                    window.switchProfile(other.profileID)
                    window.select(other.id)
                }
            }
        }

        // WebKit's own Inspect Element, carried over untouched. Nothing public
        // can put WebKit's inspector on an element, so dropping it would remove
        // the only inspection the browser has.
        if let inspect = context.inspectItem {
            menu.addItem(.separator())
            if inspect.image == nil {
                inspect.image = symbol("magnifyingglass")
            }
            menu.addItem(inspect)
        }

        // An extension's own entries, put back where WebKit had them. Replacing
        // this menu is what takes extensions' context menus away, so they are
        // carried across rather than dropped.
        if !context.extensionItems.isEmpty {
            menu.addItem(.separator())
            context.extensionItems.forEach { menu.addItem($0) }
        }
    }

    // MARK: - actions

    private static func capture(window: BrowserWindowModel, pageID: String?, forAgents: Bool) {
        guard let pageID,
              let provider = window.workspace.engine as? any BrowserPageCapturing else {
            window.alert = "Screenshots are not available in this engine."
            return
        }
        let destination = AetherCaptureLocation.folder(for: window.selected?.title)
        Task { @MainActor in
            do {
                let result = try await provider.captureLivePage(
                    pageID: pageID, into: destination, includeSource: forAgents)
                let what = forAgents ? "Capture folder" : "Screenshot"
                window.alert = result.truncated
                    ? "\(what) written to \(result.directory) — the page was taller than the capture limit, so it is partial."
                    : "\(what) written to \(result.directory)"
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.directory)])
            } catch {
                window.alert = "The capture failed: \(error.localizedDescription)"
            }
        }
    }

    private static func copyHTML(window: BrowserWindowModel, pageID: String?, forAgents: Bool) {
        guard let pageID,
              let provider = window.workspace.engine as? any BrowserPageCapturing else {
            window.alert = "Page source is not available in this engine."
            return
        }
        Task { @MainActor in
            do {
                let source = try await provider.pageSource(pageID: pageID)
                var text = source.html
                if forAgents {
                    // An agent reading this needs to know what the pieces are
                    // and where they came from, or the markup is just a wall.
                    var header = "<!-- source: \(source.url)\n     title: \(source.title)\n"
                    header += "     stylesheets: \(source.stylesheets.count)\n"
                    header += "     computed-style entries: \(source.computedStyles.count) -->\n"
                    text = header + source.html
                    if !source.stylesheets.isEmpty {
                        text += source.stylesheets.enumerated().map { index, css in
                            "\n\n/* stylesheet \(index + 1) */\n" + css
                        }.joined()
                    }
                    if let data = try? JSONSerialization.data(
                        withJSONObject: source.computedStyles, options: [.prettyPrinted, .sortedKeys]),
                       let json = String(data: data, encoding: .utf8) {
                        text += "\n\n/* computed styles */\n" + json
                    }
                }
                copy(text)
                window.alert = forAgents
                    ? "HTML, CSS and computed styles copied for an agent."
                    : "Page HTML copied."
            } catch {
                window.alert = "Could not read the page source: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - plumbing

    private static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private static func add(_ menu: NSMenu, _ title: String, symbol name: String,
                            enabled: Bool = true, action: @escaping () -> Void) {
        let item = AetherContextMenuItem(title, action: action)
        item.image = symbol(name)
        item.isEnabled = enabled
        menu.addItem(item)
    }
}

/// An `NSMenuItem` that runs a closure. Being its own target is simpler than a
/// second object to keep alive beside it.
private final class AetherContextMenuItem: NSMenuItem {
    private let act: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        act = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { act() }
}

/// Where a capture lands. Under the user's Downloads folder, one folder per
/// page, so two captures of the same page never overwrite each other.
enum AetherCaptureLocation {
    static func folder(for title: String?) -> String {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let safe = (title ?? "Page")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = safe.isEmpty ? "Page" : String(safe.prefix(60))
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        return base
            .appendingPathComponent("Aether Captures", isDirectory: true)
            .appendingPathComponent("\(stem) \(stamp)", isDirectory: true)
            .path
    }
}

/// Saving an image the page points at.
///
/// This is the item WebKit's own menu does not honour: its "Download Image"
/// never asks for a download, so nothing a download delegate could finish ever
/// arrives. Fetching the bytes directly is the same picture by a way that works.
enum AetherImageSaver {
    static func save(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent.isEmpty
            ? "image" : url.lastPathComponent
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                try? data.write(to: destination)
            }
        }
    }
}
