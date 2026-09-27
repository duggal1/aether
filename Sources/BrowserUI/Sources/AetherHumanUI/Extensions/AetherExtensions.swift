import AppKit
import Combine
import EngineRuntime
import Foundation
import SwiftUI
import WebKit

public struct AetherInstalledExtension: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var version: String
    public var enabled: Bool
    public var permissions: [String]
    public var source: String?
}

@MainActor
public final class AetherExtensions: NSObject, ObservableObject, WKWebExtensionControllerDelegate {
    public static let shared = AetherExtensions()

    @Published public private(set) var installed: [AetherInstalledExtension] = []
    @Published public private(set) var revision = 0
    @Published public private(set) var busy = false
    @Published public private(set) var error: String?

    private var controllers: [UUID: WKWebExtensionController] = [:]
    private var contexts: [UUID: [String: WKWebExtensionContext]] = [:]
    private var windows: [UUID: WeakBrowserWindow] = [:]
    private var actionAnchors: [String: WeakExtensionAnchor] = [:]
    var windowAdapters: [UUID: AetherExtensionWindow] = [:]
    fileprivate var tabAdapters: [String: AetherExtensionTab] = [:]
    private var tabOrders: [String: [UUID]] = [:]
    private var activeTabs: [UUID: UUID] = [:]
    private let extensionPopup = AetherExtensionPopup()
    /// Extensions taken up at least once this session, and ones taken up
    /// before — so a repeated WebKit "install" event (another profile's
    /// context, a reload) is told to the extension as the Chrome "update" it
    /// is, instead of opening another welcome tab.
    private var loadsThisRun: Set<String> = []
    private(set) var loadedBefore: Set<String> = []

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aether/Extensions", isDirectory: true)
    }
    private static var listURL: URL { folder.appendingPathComponent("installed.json") }

    private override init() {
        installed = (try? JSONDecoder().decode([AetherInstalledExtension].self,
                                                from: Data(contentsOf: Self.listURL))) ?? []
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeInstall(_:)), name: .aetherStoreInstall, object: nil)
        AetherWebExtensionRegistry.shared.onCreate = { [weak self] profileID, controller in
            self?.register(controller, profileID: profileID)
        }
    }

    /// The Chrome Web Store page's "Add to Aether" was pressed there: install
    /// what that tab is showing, through the same confirmation as the panel.
    @objc private func storeInstall(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String,
              Self.isStorePage(URL(string: url)) else { return }
        installFromStore(url)
    }

    /// Where "Chrome Web Store…" goes: its extensions, not its themes.
    public static let webStore = URL(string: "https://chromewebstore.google.com/category/extensions")!

    public static func isStorePage(_ url: URL?) -> Bool {
        guard let url else { return false }
        let host = url.host()?.lowercased() ?? ""
        return host == "chromewebstore.google.com"
            || (host == "chrome.google.com" && url.path.hasPrefix("/webstore"))
    }

    /// Popup pages an extension set for its button, told by the shim when
    /// `action.setPopup` runs — so the popup opened is the current one.
    var popups: [String: [String: String]] = [:]

    /// The copy an extension's popup page is loaded from, beside it.
    ///
    /// WebKit takes any page at the path of an extension's popup for its own
    /// popup, and a popup that isn't in WebKit's own view (Aether's is its
    /// own) is sent no events: no storage.onChanged, no tabs.onUpdated. A
    /// popup waiting on those never renders. So the page is loaded from a
    /// copy under another name, in the same folder: the same file, the same
    /// files around it, and none of WebKit's rules for popups. Anything else
    /// is loaded as it is.
    static let popupCopy = ".aether-popup"

    static func unpopped(_ url: URL, context: WKWebExtensionContext) -> URL {
        guard url.scheme == "chrome-extension", url.host == context.uniqueIdentifier,
              !url.lastPathComponent.contains(popupCopy)
        else { return url }
        let id = context.uniqueIdentifier
        let extra = AetherExtensions.shared.popups[id]?.values.compactMap {
            URL(string: $0, relativeTo: context.baseURL)?.absoluteURL
        } ?? []
        let named = [popupURL(for: context)] + extra
        guard named.contains(where: { $0?.path == url.path }) else { return url }
        let folder = Self.folder.appendingPathComponent(id, isDirectory: true)
        guard let original = AetherExtensionCompatibility.fileInside(url.path, of: folder),
              let data = try? Data(contentsOf: original)
        else { return url }
        let ext = original.pathExtension
        let name = original.deletingPathExtension().lastPathComponent + popupCopy + (ext.isEmpty ? "" : "." + ext)
        let copy = original.deletingLastPathComponent().appendingPathComponent(name)
        if (try? Data(contentsOf: copy)) != data {
            guard (try? data.write(to: copy, options: .atomic)) != nil else { return url }
        }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.path = (url.path as NSString).deletingLastPathComponent.appending("/" + name).replacingOccurrences(of: "//", with: "/")
        return parts.url ?? url
    }

    /// The page the manifest names for the button, when WebKit hasn't said.
    static func popupURL(for context: WKWebExtensionContext) -> URL? {
        let manifest = context.webExtension.manifest
        let action = (manifest["action"] ?? manifest["browser_action"]) as? [String: Any]
        guard let path = action?["default_popup"] as? String, !path.isEmpty else { return nil }
        // Relative to the extension, and keeping a query it may carry.
        return URL(string: path, relativeTo: context.baseURL)?.absoluteURL
    }

    public func attach(_ window: BrowserWindowModel) {
        windows[window.id] = WeakBrowserWindow(window)
        for (profileID, controller) in controllers where window.workspace.profiles.contains(where: { $0.id == profileID }) {
            if windowAdapters[window.id] == nil {
                let adapter = AetherExtensionWindow(window: window, owner: self, profileID: profileID)
                windowAdapters[window.id] = adapter
                controller.didOpenWindow(adapter)
            }
        }
        sync(window)
    }

    public func sync(_ window: BrowserWindowModel) {
        guard windows[window.id] != nil else { return }
        for profile in window.workspace.profiles where !profile.isIncognito {
            guard let controller = controllers[profile.id] else { continue }
            let adapter = windowAdapters[window.id] ?? AetherExtensionWindow(window: window, owner: self, profileID: profile.id)
            windowAdapters[window.id] = adapter
            let tabs = (window.tabsByProfile[profile.id] ?? []).filter { !window.workspace.isIncognito($0.profileID) }
            let previous = tabOrders[orderKey(window.id, profile.id)] ?? []
            let ids = tabs.map(\.id)
            for id in previous where !ids.contains(id) {
                if let tabAdapter = tabAdapters[adapterKey(window.id, id)] {
                    controller.didCloseTab(tabAdapter, windowIsClosing: false)
                }
                tabAdapters[adapterKey(window.id, id)] = nil
            }
            for tab in tabs {
                let key = adapterKey(window.id, tab.id)
                let tabAdapter = tabAdapters[key] ?? AetherExtensionTab(tab: tab, window: window, owner: self)
                tabAdapters[key] = tabAdapter
                if !previous.contains(tab.id) { controller.didOpenTab(tabAdapter) }
                else if let oldIndex = previous.firstIndex(of: tab.id),
                        let newIndex = ids.firstIndex(of: tab.id), oldIndex != newIndex {
                    controller.didMoveTab(tabAdapter, from: oldIndex, in: adapter)
                }
                controller.didChangeTabProperties([.title, .URL, .loading, .pinned], for: tabAdapter)
            }
            tabOrders[orderKey(window.id, profile.id)] = ids
            let selected = window.selectionByProfile[profile.id]
            if activeTabs[window.id] != selected {
                if extensionPopup.extensionID != nil { extensionPopup.close() }
                let old = activeTabs[window.id].flatMap { tabAdapters[adapterKey(window.id, $0)] }
                let new = selected.flatMap { tabAdapters[adapterKey(window.id, $0)] }
                if let new { controller.didActivateTab(new, previousActiveTab: old) }
                activeTabs[window.id] = selected
            }
        }
    }

    public func contexts(profileID: UUID) -> [AetherInstalledExtension: WKWebExtensionContext] {
        Dictionary(uniqueKeysWithValues: installed.compactMap { item in
            contexts[profileID]?[item.id].map { (item, $0) }
        })
    }

    public func press(_ extensionID: String, profileID: UUID) {
        if extensionPopup.extensionID == extensionID {
            extensionPopup.close()
            return
        }
        guard let context = contexts[profileID]?[extensionID],
              let window = activeWindow(profileID: profileID),
              let adapter = activeTabAdapter(in: window, profileID: profileID) else { return }
        context.userGesturePerformed(in: adapter)
        context.performAction(for: adapter)
    }

    func closePopup(_ extensionID: String) {
        if extensionPopup.extensionID == extensionID { extensionPopup.close() }
    }

    public func rememberActionAnchor(_ view: NSView, windowID: UUID, extensionID: String) {
        actionAnchors[anchorKey(windowID, extensionID)] = WeakExtensionAnchor(view)
    }

    public func actionIcon(_ extensionID: String, profileID: UUID) -> NSImage? {
        guard let context = contexts[profileID]?[extensionID],
              let window = activeWindow(profileID: profileID),
              let tab = activeTabAdapter(in: window, profileID: profileID) else { return nil }
        return context.action(for: tab)?.icon(for: NSSize(width: 20, height: 20))
            ?? context.webExtension.icon(for: NSSize(width: 20, height: 20))
    }

    public func installFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Install Extension"
        panel.message = "Choose a folder containing manifest.json."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        installFolder(at: url)
    }

    public func installFolder(at source: URL) {
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("manifest.json").path) else {
            error = "The selected folder does not contain manifest.json."
            return
        }
        let id = "local-" + UUID().uuidString.lowercased()
        let staged = Self.folder.appendingPathComponent(".staging-\(id)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.copyItem(at: source, to: staged)
            try AetherExtensionCompatibility.prepare(staged)
            Task { await admit(staged, id: id, fromStore: false, source: source) }
        } catch {
            self.error = "Aether couldn't copy the extension folder."
        }
    }

    public func installFromStore(_ text: String) {
        guard let id = AetherCRX.id(in: text) else {
            error = AetherCRX.Refused.notAnID.localizedDescription
            return
        }
        guard !installed.contains(where: { $0.id == id }) else {
            error = "This extension is already installed."
            return
        }
        busy = true
        Task {
            defer { busy = false }
            let stage = Self.folder.appendingPathComponent(".staging-\(id)", isDirectory: true)
            do {
                let data = try await AetherCRX.fetch(id)
                let zip = try AetherCRX.verifiedZip(data, id: id)
                try AetherCRX.unpack(zip, into: stage)
                try AetherExtensionCompatibility.prepare(stage)
                await admit(stage, id: id, fromStore: true, source: nil)
            } catch {
                try? FileManager.default.removeItem(at: stage)
                self.error = error.localizedDescription
            }
        }
    }

    public func setEnabled(_ id: String, enabled: Bool) {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].enabled = enabled
        persist()
        for profileID in controllers.keys {
            if enabled { load(installed[index], profileID: profileID) }
            else { unload(id, profileID: profileID) }
        }
    }

    public func remove(_ id: String) {
        for profileID in controllers.keys { unload(id, profileID: profileID) }
        loadsThisRun.remove(id)
        loadedBefore.remove(id)
        popups.removeValue(forKey: id)
        installed.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(id, isDirectory: true))
        persist()
    }

    private func register(_ controller: WKWebExtensionController, profileID: UUID) {
        controllers[profileID] = controller
        controller.delegate = self
        if let window = activeWindow(profileID: profileID) {
            let adapter = AetherExtensionWindow(window: window, owner: self, profileID: profileID)
            windowAdapters[window.id] = adapter
            controller.didOpenWindow(adapter)
            sync(window)
        }
        Task {
            for item in installed where item.enabled {
                load(item, profileID: profileID)
            }
        }
    }

    private func admit(_ staged: URL, id: String, fromStore: Bool, source: URL?) async {
        defer { busy = false }
        let extensionWeb: WKWebExtension
        do { extensionWeb = try await WKWebExtension(resourceBaseURL: staged) }
        catch {
            try? FileManager.default.removeItem(at: staged)
            self.error = "WebKit couldn't read the extension manifest: \(error.localizedDescription)"
            return
        }
        let requested = extensionWeb.requestedPermissions.map(\.rawValue).sorted()
            + extensionWeb.allRequestedMatchPatterns.map { "Website access: \($0.string)" }
        guard await confirmInstall(name: extensionWeb.displayName ?? id, permissions: requested,
                                   icon: extensionWeb.icon(for: NSSize(width: 48, height: 48))) else {
            try? FileManager.default.removeItem(at: staged)
            return
        }
        let destination = Self.folder.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: staged, to: destination)
        } catch {
            self.error = "Aether couldn't finish installing the extension."
            return
        }
        installed.removeAll { $0.id == id }
        installed.append(AetherInstalledExtension(id: id,
            name: extensionWeb.displayName ?? id,
            version: extensionWeb.version ?? "?", enabled: true,
            permissions: requested, source: source?.path))
        persist()
        for profileID in controllers.keys { load(installed[installed.count - 1], profileID: profileID) }
    }

    private func load(_ item: AetherInstalledExtension, profileID: UUID) {
        guard contexts[profileID]?[item.id] == nil,
              let controller = controllers[profileID] else { return }
        // Marked synchronously, before the context exists: the first load of
        // a session reports WebKit's "install" as-is and opens the
        // extension's welcome tab once, every later one — another profile, a
        // reload — as an update that opens nothing.
        if loadsThisRun.contains(item.id) { loadedBefore.insert(item.id) }
        loadsThisRun.insert(item.id)
        Task {
            do {
                let folder = Self.folder.appendingPathComponent(item.id)
                try AetherExtensionCompatibility.prepare(folder)
                let extensionWeb = try await WKWebExtension(resourceBaseURL: folder)
                let context = WKWebExtensionContext(for: extensionWeb)
                context.uniqueIdentifier = item.id
                guard let baseURL = URL(string: "chrome-extension://\(item.id)/") else { return }
                context.baseURL = baseURL
                context.isInspectable = true
                for permission in extensionWeb.requestedPermissions {
                    context.setPermissionStatus(.grantedExplicitly, for: permission)
                }
                for pattern in extensionWeb.allRequestedMatchPatterns {
                    context.setPermissionStatus(.grantedExplicitly, for: pattern)
                }
                context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
                try controller.load(context)
                contexts[profileID, default: [:]][item.id] = context
                revision &+= 1
            } catch {
                self.error = "\(item.name) couldn't start: \(error.localizedDescription)"
            }
        }
    }

    private func unload(_ id: String, profileID: UUID) {
        guard let context = contexts[profileID]?[id] else { return }
        try? controllers[profileID]?.unload(context)
        contexts[profileID]?[id] = nil
        revision &+= 1
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(installed).write(to: Self.listURL, options: .atomic)
            revision &+= 1
        } catch {
            self.error = "Aether couldn't save the extension list."
        }
    }

    private func confirmInstall(name: String, permissions: [String], icon: NSImage?) async -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Install \(name)?"
            alert.informativeText = permissions.isEmpty
                ? "This extension does not request additional browser permissions."
                : "It requests: \(permissions.joined(separator: ", "))"
            alert.icon = icon
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }

    private func confirmPermission(_ title: String, detail: String) async -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Don't Allow")
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0 == .alertFirstButtonReturn) }
        }
    }

    private func activeWindow(profileID: UUID) -> BrowserWindowModel? {
        windows.values.compactMap(\.value).first { $0.workspace.profiles.contains(where: { $0.id == profileID }) }
    }

    private func activeTabAdapter(in window: BrowserWindowModel, profileID: UUID) -> AetherExtensionTab? {
        guard let id = window.selectionByProfile[profileID] else { return nil }
        return tabAdapters[adapterKey(window.id, id)]
    }

    func windowAdapter(for window: BrowserWindowModel, profileID: UUID) -> AetherExtensionWindow {
        if let adapter = windowAdapters[window.id], adapter.profileID == profileID { return adapter }
        let adapter = AetherExtensionWindow(window: window, owner: self, profileID: profileID)
        windowAdapters[window.id] = adapter
        return adapter
    }

    private func profileID(for controller: WKWebExtensionController) -> UUID? {
        controllers.first(where: { $0.value === controller })?.key
    }

    func controller(profileID: UUID) -> WKWebExtensionController? {
        controllers[profileID]
    }

    private func ownerWindow(for context: WKWebExtensionContext) -> BrowserWindowModel? {
        guard let profileID = controllers.first(where: { $0.value === context.webExtensionController })?.key else { return nil }
        return activeWindow(profileID: profileID)
    }

    private func adapterKey(_ window: UUID, _ tab: UUID) -> String { "\(window.uuidString):\(tab.uuidString)" }
    private func orderKey(_ window: UUID, _ profile: UUID) -> String { "\(window.uuidString):\(profile.uuidString)" }
    private func anchorKey(_ window: UUID, _ extensionID: String) -> String { "\(window.uuidString):\(extensionID)" }

    // WKWebExtensionControllerDelegate
    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        guard let profileID = profileID(for: controller) else { return [] }
        return windows.values.compactMap(\.value).filter { $0.workspace.profiles.contains(where: { $0.id == profileID }) }
            .map { windowAdapters[$0.id] ?? AetherExtensionWindow(window: $0, owner: self, profileID: profileID) }
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let profileID = profileID(for: controller), let window = activeWindow(profileID: profileID) else { return nil }
        return windowAdapters[window.id] ?? AetherExtensionWindow(window: window, owner: self, profileID: profileID)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        guard let profileID = profileID(for: controller), let window = activeWindow(profileID: profileID) else { return nil }
        let tab = window.newTab(select: configuration.shouldBeActive)
        if let url = configuration.url { window.navigateExtension(tab, to: url) }
        if configuration.shouldBePinned { tab.isPinned = true }
        sync(window)
        return tabAdapters[adapterKey(window.id, tab.id)]
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        guard let profileID = profileID(for: controller), let window = activeWindow(profileID: profileID) else { return nil }
        for (index, url) in configuration.tabURLs.enumerated() {
            let tab = window.newTab(select: index == 0 && configuration.shouldBeFocused)
            window.navigateExtension(tab, to: url)
        }
        sync(window)
        return windowAdapters[window.id]
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        guard let url = extensionContext.optionsPageURL,
              let window = ownerWindow(for: extensionContext) else { return }
        let tab = window.newTab()
        window.navigateExtension(tab, to: url)
        sync(window)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        let list = permissions.map(\.rawValue).sorted().joined(separator: ", ")
        let name = extensionContext.webExtension.displayName ?? "An extension"
        return await confirmPermission("\(name) requests more access", detail: list) ? (permissions, nil) : ([], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        ([], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>, in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let scope = patterns.contains(where: { $0.matchesAllHosts || $0.matchesAllURLs })
            ? "all websites" : patterns.map(\.string).sorted().joined(separator: ", ")
        let name = extensionContext.webExtension.displayName ?? "An extension"
        return await confirmPermission("\(name) wants website access", detail: scope) ? (patterns, nil) : ([], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                       forExtensionContext context: WKWebExtensionContext) {
        revision &+= 1
    }

    public func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any,
        toApplicationWithIdentifier identifier: String?, for extensionContext: WKWebExtensionContext) async throws -> Any? {
        guard let identifier else { return nil }
        return try await AetherExtensionNative.send(message, to: identifier, from: extensionContext.uniqueIdentifier)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort,
                                       for extensionContext: WKWebExtensionContext) async throws {
        if port.applicationIdentifier == AetherExtensionSocket.name {
            AetherExtensionSocket.connect(port, from: extensionContext.uniqueIdentifier)
        } else {
            try AetherExtensionNative.connect(port, from: extensionContext.uniqueIdentifier)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext) async throws {
        guard let profileID = profileID(for: controller),
              let window = activeWindow(profileID: profileID),
              let anchor = actionAnchors[anchorKey(window.id, extensionContext.uniqueIdentifier)]?.value,
              let url = action.popupWebView?.url else { return }
        action.closePopup()
        extensionPopup.show(url, context: extensionContext, owner: self, window: window,
                            profileID: profileID, anchor: anchor)
    }
}

@MainActor
private final class WeakBrowserWindow {
    weak var value: BrowserWindowModel?
    init(_ value: BrowserWindowModel) { self.value = value }
}

@MainActor
private final class WeakExtensionAnchor {
    weak var value: NSView?
    init(_ value: NSView) { self.value = value }
}

@MainActor
final class AetherExtensionWindow: NSObject, WKWebExtensionWindow {
    weak var window: BrowserWindowModel?
    unowned let owner: AetherExtensions
    let profileID: UUID
    init(window: BrowserWindowModel, owner: AetherExtensions, profileID: UUID) {
        self.window = window; self.owner = owner; self.profileID = profileID
    }
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let window else { return [] }
        return (window.tabsByProfile[profileID] ?? []).compactMap { tab in
            owner.tabAdapters["\(window.id.uuidString):\(tab.id.uuidString)"]
        }
    }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let window, let id = window.selectionByProfile[profileID] else { return nil }
        return owner.tabAdapters["\(window.id.uuidString):\(id.uuidString)"]
    }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let native = window?.nativeWindow else { return .normal }
        if native.isMiniaturized { return .minimized }
        if native.styleMask.contains(.fullScreen) { return .fullscreen }
        return native.isZoomed ? .maximized : .normal
    }
    func frame(for context: WKWebExtensionContext) -> CGRect { window?.nativeWindow?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window?.nativeWindow?.screen?.frame ?? NSScreen.main?.frame ?? .null }
    func focus(for context: WKWebExtensionContext) async throws {
        NSApp.activate(ignoringOtherApps: true)
        window?.nativeWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
fileprivate final class AetherExtensionTab: NSObject, WKWebExtensionTab {
    weak var tab: BrowserTab?
    weak var window: BrowserWindowModel?
    unowned let owner: AetherExtensions
    init(tab: BrowserTab, window: BrowserWindowModel, owner: AetherExtensions) {
        self.tab = tab; self.window = window; self.owner = owner
    }
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let window else { return nil }
        guard let tab else { return nil }
        return owner.windowAdapter(for: window, profileID: tab.profileID)
    }
    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        guard let tab, let window else { return NSNotFound }
        return (window.tabsByProfile[tab.profileID] ?? []).firstIndex(where: { $0.id == tab.id }) ?? NSNotFound
    }
    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        guard let pageID = tab?.enginePageID else { return nil }
        return window?.workspace.engine.surface(pageID: pageID) as? WKWebView
    }
    func title(for context: WKWebExtensionContext) -> String? { tab?.title }
    func url(for context: WKWebExtensionContext) -> URL? { tab?.url.flatMap(URL.init(string:)) }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(tab?.isLoading ?? false) }
    func isSelected(for context: WKWebExtensionContext) -> Bool { tab?.id == window?.selectedID }
    func isPinned(for context: WKWebExtensionContext) -> Bool { tab?.isPinned ?? false }
    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool { false }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { Double((webView(for: context)?.pageZoom) ?? 1) }
    func size(for context: WKWebExtensionContext) -> CGSize { webView(for: context)?.bounds.size ?? .zero }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }
    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext) async throws {
        guard let tab, let window else { return }
        tab.isPinned = pinned
        owner.sync(window)
    }
    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws {
        webView(for: context)?.pageZoom = CGFloat(zoomFactor)
    }
    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        guard let tab, let window else { return }
        window.navigateExtension(tab, to: url)
    }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        if fromOrigin { webView(for: context)?.reloadFromOrigin() } else { webView(for: context)?.reload() }
    }
    func goBack(for context: WKWebExtensionContext) async throws { webView(for: context)?.goBack() }
    func goForward(for context: WKWebExtensionContext) async throws { webView(for: context)?.goForward() }
    func activate(for context: WKWebExtensionContext) async throws {
        guard let tab, let window else { return }
        window.switchProfile(tab.profileID)
        window.select(tab.id)
    }
    func close(for context: WKWebExtensionContext) async throws {
        guard let tab, let window else { return }
        window.close(tab.id)
    }
    func takeSnapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext) async throws -> NSImage? {
        guard let webView = webView(for: context) else { return nil }
        return try await webView.takeSnapshot(configuration: configuration)
    }
}
