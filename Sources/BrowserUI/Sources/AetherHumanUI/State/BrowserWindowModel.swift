import AppKit
import EngineRuntime
import Foundation
import WebKit
import Observation

@MainActor @Observable
public final class BrowserWindowModel: Identifiable {
    public private(set) static weak var front: BrowserWindowModel?
    public let id = UUID()
    public let workspace: BrowserWorkspace
    public let surfaces = PageSurfaceRegistry()
    public var activeProfileID: UUID
    public var isIncognito = false
    @ObservationIgnored private var incognitoReturnProfileID: UUID?
    public var sidebarCollapsed = false
    public var showsTabSearch = false
    public var showsHistory = false
    public var showsBookmarks = false
    public var showsProfileMenu = false
    public var showsMoreMenu = false
    /// The extensions drawer beside the space switcher. Its own state, so the
    /// list can be open while nothing else is.
    public var showsExtensionsMenu = false
    /// What Jev has judged about the page in front.
    public var showsJevSignals = false
    public var showsNewProfile = false
    public var showsRenameProfile = false
    public var showsDownloads = false
    public var showsInspector = false
    public var showsReader = false
    public var showsFind = false
    public var showsSettings = false
    // MARK: - Search-port chrome state
    public var showsTabSwitcher = false
    public var showsBookmarksBarOverride: Bool? = nil
    public var showsWelcome = false
    public var showsSiteCard = false
    public var peekURL: String? = nil
    public var peekTitle: String = ""
    public var renamingTabID: UUID? = nil
    public var siteZoom: [String: Double] = [:]
    public var showsVeils = false
    public var findQuery = ""
    public var addressFocusNonce = 0
    public let suggestions = OmniboxSuggestionModel()
    public var alert: String?
    public var hoveredLink: String?
    public private(set) var agentInteraction: AgentInteractionUpdate?
    public var linkPreviewOnRight = false
    public var credentialSaveOffer: AetherCredential?
    @ObservationIgnored var pageInteractionRelays: [String: PageInteractionRelay] = [:]
    @ObservationIgnored private var mouseNavigationMonitor: Any?
    @ObservationIgnored private var tabShortcutMonitor: Any?
    @ObservationIgnored private var agentInteractionObservation: Task<Void, Never>?
    @ObservationIgnored private var agentInteractionClearTask: Task<Void, Never>?
    @ObservationIgnored private var humanPointerMonitor: Any?
    @ObservationIgnored weak var nativeWindow: NSWindow?
    @ObservationIgnored private let floater = Float()
    @ObservationIgnored private let credentialPopover = AetherCredentialPopover()
    @ObservationIgnored private var pendingCredentialSaves: [String: AetherCredential] = [:]
    public private(set) var floatingPageID: String?
    public private(set) var glow = AetherNavigationGlowState()
    @ObservationIgnored private var navigationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var navigationEpochs: [UUID: UInt64] = [:]
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var enginePageIndex: [String: BrowserTab] = [:]
    @ObservationIgnored private var restorationStarted = false
    @ObservationIgnored private var lastNavigationURLs: [String: String] = [:]
    @ObservationIgnored private var sleepTimer: Timer?
    public private(set) var closedTabs: [ClosedTab] = []
    public private(set) var tabsByProfile: [UUID: [BrowserTab]] = [:]
    public private(set) var selectionByProfile: [UUID: UUID] = [:]

    public var arrangement: TabArrangement { workspace.preferences.arrangement }
    public var tabs: [BrowserTab] { tabsByProfile[activeProfileID] ?? [] }
    public var selectedID: UUID? { selectionByProfile[activeProfileID] }
    public var selected: BrowserTab? { tabs.first(where: { $0.id == selectedID }) }

    public init(workspace: BrowserWorkspace) {
        self.workspace = workspace
        self.activeProfileID = workspace.defaultProfileID
        let first = BrowserTab(profileID: activeProfileID)
        tabsByProfile[activeProfileID] = [first]
        selectionByProfile[activeProfileID] = first.id
        workspace.addWindow(self)
        AetherExtensions.shared.attach(self)
        mouseNavigationMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, event.buttonNumber == 3 || event.buttonNumber == 4,
                  let pageID = self.selected?.enginePageID,
                  let webView = self.workspace.engine.surface(pageID: pageID),
                  event.window === webView.window,
                  webView.bounds.contains(webView.convert(event.locationInWindow, from: nil)) else { return event }
            if event.buttonNumber == 3 { self.perform(.back) }
            else { self.perform(.forward) }
            return nil
        }
        tabShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.nativeWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if flags == .command, key == "s", !Self.responderIsInPage(event.window?.firstResponder) {
                self.toggleSidebar()
                return nil
            }
            guard flags == .command,
                  let number = Self.topRowDigitKeys[event.keyCode] else { return event }
            self.selectTab(number: number)
            return nil
        }
        humanPointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, event.window === self.nativeWindow else { return event }
            self.takeHumanControl()
            return event
        }
        if let observing = workspace.engine as? any BrowserAgentInteractionObserving {
            agentInteractionObservation = Task { [weak self] in
                let updates = await observing.agentInteractionUpdates()
                for await update in updates {
                    guard let self, !Task.isCancelled else { return }
                    guard self.selected?.enginePageID == update.pageID.description else { continue }
                    let point = update.point ?? self.agentInteraction?.point
                    let viewport = update.viewport ?? self.agentInteraction?.viewport
                    let luminance = update.targetLuminance ?? self.agentInteraction?.targetLuminance
                    self.agentInteraction = AgentInteractionUpdate(sequence: update.sequence,
                        pageID: update.pageID, kind: update.kind, point: point, viewport: viewport,
                        targetLuminance: luminance, movementDuration: update.movementDuration)
                    if update.kind != .idle {
                        NSCursor.setHiddenUntilMouseMoves(true)
                    } else {
                        self.agentInteractionClearTask?.cancel()
                        self.agentInteractionClearTask = Task { [weak self] in
                            try? await Task.sleep(for: .milliseconds(280))
                            guard !Task.isCancelled, let self,
                                  self.agentInteraction?.sequence == update.sequence else { return }
                            self.agentInteraction = nil
                        }
                    }
                }
            }
        }
        AetherLatencyProbe.mark("model.created")
        // Search-port: watchForSleep — every minute, sleep tabs idle 30 min.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepIdleTabs() }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
        if let observing = workspace.engine as? any BrowserPageObserving {
            let updates = observing.pageUpdates()
            observation = Task { [weak self] in
                for await state in updates {
                    guard let self, !Task.isCancelled else { return }
                    if let tab = self.tab(forEnginePage: state.id) {
                        self.apply(state, to: tab)
                    }
                }
            }
        }
    }
    deinit {
        if let mouseNavigationMonitor { NSEvent.removeMonitor(mouseNavigationMonitor) }
        if let tabShortcutMonitor { NSEvent.removeMonitor(tabShortcutMonitor) }
        if let humanPointerMonitor { NSEvent.removeMonitor(humanPointerMonitor) }
        agentInteractionObservation?.cancel()
        agentInteractionClearTask?.cancel()
        sleepTimer?.invalidate()
    }
    private static let topRowDigitKeys: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]
    private static func responderIsInPage(_ responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view {
            if current is AetherPageView { return true }
            view = current.superview
        }
        return false
    }
    private var liftedAway = false

    public func becameKeyWindow() { Self.front = self }

    public func clearAgentCursor() {
        agentInteractionClearTask?.cancel()
        agentInteraction = nil
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    public func takeHumanControl() {
        let pageID = agentInteraction?.pageID.description ?? selected?.enginePageID
        clearAgentCursor()
        guard let pageID,
              let observing = workspace.engine as? any BrowserAgentInteractionObserving else { return }
        Task { await observing.cancelAgentInteraction(pageID: pageID) }
    }

    public func takeHumanControl(from pageID: String) {
        clearAgentCursor()
        guard let observing = workspace.engine as? any BrowserAgentInteractionObserving else { return }
        Task { await observing.cancelAgentInteraction(pageID: pageID) }
    }

    public func applicationWillResignActive() {
        takeHumanControl()
        guard Self.front === self, workspace.preferences.floatVideoWhenSwitchingApps else { return }
        liftedAway = floatingPageID == nil
        if let selected { floatVideo(from: selected, requireSelection: true, quietly: true) }
    }

    public func applicationDidBecomeActive() {
        defer { liftedAway = false }
        if liftedAway, let floatingPageID, selected?.enginePageID == floatingPageID { landVideo() }
    }

    private static func isKnownVideoSite(_ rawURL: String?) -> Bool {
        guard let rawURL, let url = URL(string: rawURL), let host = url.host?.lowercased() else { return false }
        let sites: [(String, String?)] = [
            ("youtube.com", nil), ("youtu.be", nil), ("netflix.com", nil),
            ("primevideo.com", nil), ("amazon.com", "/gp/video"), ("amazon.fr", "/gp/video"),
            ("amazon.co.uk", "/gp/video"), ("amazon.de", "/gp/video"),
            ("disneyplus.com", nil), ("tv.apple.com", nil), ("twitch.tv", nil),
            ("vimeo.com", nil), ("dailymotion.com", nil), ("max.com", nil), ("hbomax.com", nil),
            ("canalplus.com", nil), ("mycanal.fr", nil), ("arte.tv", nil), ("france.tv", nil),
            ("tf1.fr", nil), ("6play.fr", nil), ("crunchyroll.com", nil), ("plex.tv", nil),
            ("peacocktv.com", nil), ("hulu.com", nil), ("paramountplus.com", nil),
            ("molotov.tv", nil), ("ocs.fr", nil), ("mubi.com", nil), ("criterionchannel.com", nil),
            ("ted.com", nil), ("nebula.tv", nil), ("curiositystream.com", nil)
        ]
        return sites.contains { site, path in
            guard host == site || host.hasSuffix("." + site) else { return false }
            return path.map { url.path.lowercased().hasPrefix($0) } ?? true
        }
    }
    public func restoreProfile() async {
        guard !restorationStarted, workspace.preferences.restoreWindows else { return }
        restorationStarted = true
        if restoreSavedSessionTabs() { return }
        guard let provider = workspace.engine as? any BrowserProfileManaging else { return }
        let profile = activeProfileID
        do {
            let restored = try await provider.restoredPages(profileID: profile)
            guard !restored.isEmpty else { return }
            let tabs = restored.map { state in
                let tab = BrowserTab(profileID: profile)
                tab.enginePageID = state.id
                enginePageIndex[state.id] = tab
                apply(state, to: tab)
                return tab
            }
            if tabsByProfile[profile]?.count == 1 && tabsByProfile[profile]?.first?.loadState == .newTab {
                tabsByProfile[profile] = tabs
            } else { tabsByProfile[profile, default: []] += tabs }
            selectionByProfile[profile] = tabs.first?.id
        } catch { alert = error.localizedDescription }
    }

    @discardableResult private func restoreSavedSessionTabs() -> Bool {
        let session = workspace.savedSession()
        guard let record = session.windows.first(where: { $0.id == id }) ?? session.windows.first,
              workspace.profiles.contains(where: { $0.id == record.activeProfileID }),
              !(tabsByProfile[record.activeProfileID] ?? []).isEmpty == false
                || (tabsByProfile[activeProfileID]?.count == 1
                    && tabsByProfile[activeProfileID]?.first?.loadState == .newTab),
              !(record.tabs.filter { $0.profileID == record.activeProfileID }).isEmpty
        else { return false }
        let known = Set(workspace.profiles.map(\.id))
        var grouped: [UUID: [BrowserTab]] = [:]
        for saved in record.tabs where known.contains(saved.profileID) {
            let tab = BrowserTab(id: saved.id, profileID: saved.profileID, title: saved.title, url: saved.url)
            tab.customTitle = saved.customTitle
            tab.isPinned = saved.isPinned
            if saved.url != nil {
                tab.loadState = .ready
                tab.needsRestoreLoad = true
            }
            grouped[saved.profileID, default: []].append(tab)
        }
        guard !grouped[record.activeProfileID, default: []].isEmpty else { return false }
        activeProfileID = record.activeProfileID
        isIncognito = workspace.isIncognito(activeProfileID)
        sidebarCollapsed = record.sidebarCollapsed
        tabsByProfile = grouped
        selectionByProfile = [:]
        for (profileID, items) in grouped {
            let wanted = record.selectedByProfile[profileID] ?? items.first?.id
            selectionByProfile[profileID] = items.first(where: { $0.id == wanted })?.id ?? items.first?.id
        }
        if let tab = selected, tab.needsRestoreLoad, let url = tab.url {
            tab.needsRestoreLoad = false
            navigate(tab, text: url)
        }
        workspace.flushSession()
        return true
    }

    public func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        guard id != selectedID else {
            if let tab = tabs.first(where: { $0.id == id }) { tab.lastActiveAt = Date() }
            return
        }
        let incoming = tabs.first(where: { $0.id == id })
        if incoming?.enginePageID == floatingPageID { landVideo() }
        else if workspace.preferences.floatVideoWhenSwitchingTabs, let leaving = selected {
            floatVideo(from: leaving, requireSelection: false, quietly: true)
        }
        credentialPopover.close()
        hoveredLink = nil
        closeMenus()
        selectionByProfile[activeProfileID] = id
        AetherExtensions.shared.sync(self)
        if let tab = tabs.first(where: { $0.id == id }) {
            tab.lastActiveAt = Date()
            // Search-port: wake sleeping tab on select.
            if tab.isSleeping {
                tab.isSleeping = false
                tab.needsRestoreLoad = true
            }
            if tab.needsRestoreLoad, let url = tab.url {
                tab.needsRestoreLoad = false
                navigate(tab, text: url)
            }
        }
        workspace.scheduleSessionSave()
    }
    /// Search-port: pinned squares — Cmd+W puts down (unpins) instead of closing.
    public func closeOrPutDown(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.isPinned { tab.isPinned = false; workspace.scheduleSessionSave(); return }
        close(id)
    }
    public func zoomForHost(_ host: String?) -> Double { siteZoom[host?.lowercased() ?? ""] ?? 1.0 }
    public func setZoom(_ value: Double, host: String?) {
        guard let host = host?.lowercased(), !host.isEmpty else { return }
        let clamped = min(3.0, max(0.25, value))
        if abs(clamped - 1.0) < 0.01 { siteZoom.removeValue(forKey: host) }
        else { siteZoom[host] = clamped }
    }
    public func selectTab(number: Int) {
        guard number >= 1, !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        select(tabs[index].id)
    }

    public func copyMarkdownLink(for tab: BrowserTab? = nil) {
        guard let tab = tab ?? selected, let raw = tab.url,
              let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let title = (tab.title.isEmpty ? url.host ?? raw : tab.title)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        let destination = url.absoluteString.replacingOccurrences(of: ">", with: "%3E")
        let board = NSPasteboard.general
        board.clearContents()
        board.setString("[\(title)](<\(destination)>)", forType: .string)
    }

    public func sharePage(for tab: BrowserTab? = nil) {
        guard let tab = tab ?? selected, let raw = tab.url,
              let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let view = NSApp.keyWindow?.contentView else { return }
        let anchor = NSRect(x: view.bounds.maxX - 16, y: view.bounds.maxY - 16, width: 1, height: 1)
        NSSharingServicePicker(items: [url]).show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }

    public func toggleMute(_ tab: BrowserTab? = nil) {
        guard let tab = tab ?? selected else { return }
        tab.isMuted.toggle()
        if !tab.isMuted { tab.muteAppliedURL = nil }
        applyAudioMute(tab)
        if tab.isMuted { tab.muteAppliedURL = tab.url }
    }

    /// The palette for the bubble that hangs off a password field.
    ///
    /// It sits on the page, not on the desktop, so it resolves from the page's
    /// own tone: a saved-password bubble on a white login page used to render as
    /// a black box for exactly the reason the cards did.
    private func credentialSurface(for tab: BrowserTab) -> AetherSurfaceStyle {
        let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return AetherSurfaceResolver.style(tab.surfaceAppearance ?? .lightWebsite, darkHomepage: systemDark)
    }

    public func receiveCredentialEvent(_ event: AetherCredentialEvent, pageID: String, pageView: AetherPageView) {
        guard let tab = tab(forEnginePage: pageID) else { return }
        guard !workspace.isIncognito(tab.profileID) else {
            pendingCredentialSaves[pageID] = nil
            credentialPopover.close()
            return
        }
        switch event {
        case let .focus(origin, username, rect, passwordField, passwordCreation):
            guard selected?.enginePageID == pageID,
                  AetherCredentialVault.origin(for: pageView.url?.absoluteString ?? "") == origin,
                  Self.allowsCredentialOrigin(origin) else { return }
            guard let provider = workspace.engine as? any BrowserCredentialVaultProviding else { return }
            Task { [weak self, weak pageView] in
                do {
                    let choices = try await provider.savedCredentials(profileID: tab.profileID, origin: origin)
                        .filter { username.isEmpty || $0.username == username }
                    guard let self, let pageView,
                          self.selected?.enginePageID == pageID,
                          !self.workspace.isIncognito(tab.profileID),
                          AetherCredentialVault.origin(for: pageView.url?.absoluteString ?? "") == origin else { return }
                    let zoom = pageView.pageZoom
                    let anchor = CGRect(x: rect.minX * zoom,
                                        y: pageView.bounds.height - (rect.maxY * zoom),
                                        width: max(1, rect.width * zoom), height: max(1, rect.height * zoom))
                    self.credentialPopover.show(in: pageView, pageRect: anchor, choices: choices,
                                                canGenerate: passwordField && passwordCreation,
                                                surface: self.credentialSurface(for: tab),
                                                choose: { credential in
                        Task {
                            guard !self.workspace.isIncognito(credential.profileID),
                                  self.selected?.enginePageID == pageID else { return }
                            do {
                                try await provider.fillCredential(
                                    pageID: pageID, credentialID: credential.id,
                                    fillUsername: !passwordField)
                            } catch {
                                self.alert = error.localizedDescription
                            }
                        }
                    }, generate: { [weak pageView] in
                        let generated = AetherCredentialVault.generatePassword()
                        guard !generated.isEmpty else { return }
                        pageView?.fillGeneratedPassword(generated)
                    })
                } catch {
                    guard let self else { return }
                    self.alert = error.localizedDescription
                }
            }
        case let .submitted(origin, username, password):
            guard AetherCredentialVault.origin(for: origin) == origin,
                  Self.allowsCredentialOrigin(origin), !password.isEmpty else { return }
            pendingCredentialSaves[pageID] = AetherCredential(profileID: tab.profileID,
                                                               origin: origin,
                                                               username: username,
                                                               password: password)
        case let .settled(origin):
            guard let candidate = pendingCredentialSaves[pageID], candidate.origin == origin else { return }
            pendingCredentialSaves[pageID] = nil
            credentialSaveOffer = candidate
        }
    }

    public func acceptCredentialSave() {
        guard let credential = credentialSaveOffer,
              !workspace.isIncognito(credential.profileID) else {
            credentialSaveOffer = nil
            return
        }
        credentialSaveOffer = nil
        guard let provider = workspace.engine as? any BrowserCredentialVaultProviding else {
            alert = "Aether couldn't connect to its credential store."
            return
        }
        Task {
            do {
                try await provider.saveCredential(
                    profileID: credential.profileID, origin: credential.origin,
                    username: credential.username, password: credential.password)
            } catch { alert = error.localizedDescription }
        }
    }

    public func dismissCredentialSave() { credentialSaveOffer = nil }

    private static func allowsCredentialOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        guard scheme == "http", let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
    }

    private func applyAudioMute(_ tab: BrowserTab) {
        guard let pageID = tab.enginePageID,
              let webView = workspace.engine.surface(pageID: pageID) as? WKWebView else { return }
        webView.evaluateJavaScript(WebKitTabAudio.command(muted: tab.isMuted)) { _, _ in }
    }

    @discardableResult public func newTab(url: String? = nil, select: Bool = true) -> BrowserTab {
        closeMenus()
        let tab = BrowserTab(profileID: activeProfileID)
        tab.lastActiveAt = Date()
        tabsByProfile[activeProfileID, default: []].append(tab)
        if select { selectionByProfile[activeProfileID] = tab.id }
        if let url { navigate(tab, text: url) }
        AetherExtensions.shared.sync(self)
        workspace.scheduleSessionSave()
        return tab
    }
    // MARK: - Search-port: tab extras (rename, open-beside, private, sleep)
    public func renameTab(_ id: UUID, to name: String) {
        guard let tab = tabsByProfile[activeProfileID]?.first(where: { $0.id == id }) else { return }
        tab.customTitle = name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120).description
        workspace.scheduleSessionSave()
    }
    @discardableResult public func openBeside(url: String, select: Bool = true) -> BrowserTab {
        closeMenus()
        let tab = BrowserTab(profileID: activeProfileID)
        tab.lastActiveAt = Date()
        var list = tabsByProfile[activeProfileID, default: []]
        if let i = list.firstIndex(where: { $0.id == selectedID }) { list.insert(tab, at: i + 1) }
        else { list.append(tab) }
        tabsByProfile[activeProfileID] = list
        if select { selectionByProfile[activeProfileID] = tab.id }
        navigate(tab, text: url)
        AetherExtensions.shared.sync(self)
        workspace.scheduleSessionSave()
        return tab
    }
    @discardableResult public func newPrivateTab(url: String? = nil) -> BrowserTab {
        closeMenus()
        let tab = BrowserTab(profileID: activeProfileID)
        tab.isPrivateTab = true
        tab.lastActiveAt = Date()
        tabsByProfile[activeProfileID, default: []].append(tab)
        selectionByProfile[activeProfileID] = tab.id
        if let url { navigate(tab, text: url) }
        AetherExtensions.shared.sync(self)
        workspace.scheduleSessionSave()
        return tab
    }
    public func sleepTab(_ id: UUID) {
        guard workspace.preferences.sleepTabsEnabled,
              let tab = tabsByProfile[activeProfileID]?.first(where: { $0.id == id }),
              tab.id != selectedID, !tab.isPinned, !tab.isSleeping,
              tab.enginePageID != nil, tab.url != nil else { return }
        if tab.isMuted { return }
        if floatingPageID == tab.enginePageID { return }
        if let page = tab.enginePageID {
            pageInteractionRelays.removeValue(forKey: page)
            surfaces.release(page); forgetEnginePage(page)
            Task { await workspace.engine.close(pageID: page) }
            tab.enginePageID = nil
        }
        tab.isSleeping = true
        tab.needsRestoreLoad = true
        workspace.scheduleSessionSave()
    }
    public func sleepIdleTabs(olderThan interval: TimeInterval = 30 * 60) {
        guard workspace.preferences.sleepTabsEnabled else { return }
        let now = Date()
        for tab in tabs where now.timeIntervalSince(tab.lastActiveAt) >= interval {
            sleepTab(tab.id)
        }
    }
    public func switchProfile(_ id: UUID) {
        guard workspace.profiles.contains(where: { $0.id == id }) else { return }
        credentialPopover.close()
        let leavingIncognito = isIncognito && activeProfileID != id
        activeProfileID = id
        AetherExtensions.shared.sync(self)
        if tabsByProfile[id, default: []].isEmpty { _ = newTab() }
        isIncognito = workspace.isIncognito(id)
        workspace.scheduleSessionSave()
        if isIncognito {
            Task { try? await workspace.engine.setProfileEphemeral(profileID: id, enabled: true) }
        } else if leavingIncognito, let incognitoID = workspace.profiles.first(where: \.isIncognito)?.id {
            Task { try? await workspace.engine.setProfileEphemeral(profileID: incognitoID, enabled: false) }
        }
    }
    public func setIncognito(_ enabled: Bool) {
        if enabled {
            guard !isIncognito else { return }
            let profile = workspace.ensureIncognitoProfile()
            incognitoReturnProfileID = activeProfileID
            switchProfile(profile.id)
            Task {
                do {
                    var policy = workspace.preferences.privacy
                    policy.hideIP = true
                    try await workspace.engine.updatePrivacy(profileID: profile.id, policy: policy)
                } catch { alert = error.localizedDescription }
            }
        } else {
            guard isIncognito else { return }
            incognitoReturnProfileID = nil
            switchProfile(workspace.defaultProfileID)
        }
    }
    public func removeProfile(_ id: UUID, switchTo next: UUID) {
        for tab in tabsByProfile[id] ?? [] {
            navigationTasks.removeValue(forKey: tab.id)?.cancel()
            if let page = tab.enginePageID { surfaces.release(page); forgetEnginePage(page); Task { await workspace.engine.close(pageID: page) } }
        }
        tabsByProfile.removeValue(forKey: id)
        selectionByProfile.removeValue(forKey: id)
        closedTabs.removeAll { $0.profileID == id }
        if activeProfileID == id { switchProfile(next) }
    }
    public func close(_ id: UUID) { close(ids: [id]) }

    /// Closing several tabs is one change to the window, not several.
    ///
    /// Each tab still goes down on its own — its navigation cancelled, its page
    /// released, its place kept for restore — but the list is rebuilt once, the
    /// extensions are told once and the session is written once, instead of all
    /// three happening again for every tab. "Close others" on a window of forty
    /// used to be forty of each.
    public func close(ids: [UUID]) {
        let closing = Set(ids)
        guard !closing.isEmpty, let list = tabsByProfile[activeProfileID] else { return }
        var removed = 0
        var closedSelectedAt: Int?
        for (index, tab) in list.enumerated() where closing.contains(tab.id) {
            if floatingPageID == tab.enginePageID { landVideo() }
            navigationTasks.removeValue(forKey: tab.id)?.cancel()
            if case .newTab = tab.loadState {
            } else if case .search = tab.loadState {
            } else if let url = tab.url, !url.isEmpty, url != "about:blank" {
                closedTabs.insert(ClosedTab(title: tab.title.isEmpty ? url : tab.title, url: tab.url, profileID: tab.profileID), at: 0)
                if closedTabs.count > 30 { closedTabs.removeLast() }
            }
            if let page = tab.enginePageID {
                pageInteractionRelays.removeValue(forKey: page)
                surfaces.release(page); forgetEnginePage(page); Task { await workspace.engine.close(pageID: page) }
            }
            removed += 1
            if tab.id == selectedID { closedSelectedAt = index }
        }
        guard removed > 0 else { return }
        let remaining = list.filter { !closing.contains($0.id) }
        tabsByProfile[activeProfileID] = remaining
        AetherExtensions.shared.sync(self)
        // The tab after the one that went takes its place, as it always has; with
        // several gone at once that means the first tab that followed the last
        // selected one of them.
        if let index = closedSelectedAt {
            selectionByProfile[activeProfileID] =
                remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
        if tabs.isEmpty { _ = newTab() }
        workspace.scheduleSessionSave()
    }

    public func closeOthers(_ id: UUID) {
        close(ids: tabs.filter { $0.id != id && !$0.isPinned }.map(\.id))
    }
    public func togglePin(_ id: UUID) {
        tabs.first(where: { $0.id == id })?.isPinned.toggle()
        workspace.scheduleSessionSave()
    }
    public func moveTab(_ source: UUID, before target: UUID) {
        guard var items = tabsByProfile[activeProfileID], let from = items.firstIndex(where: { $0.id == source }),
              let to = items.firstIndex(where: { $0.id == target }), from != to else { return }
        let moved = items.remove(at: from)
        items.insert(moved, at: min(to, items.count))
        tabsByProfile[activeProfileID] = items
        AetherExtensions.shared.sync(self)
        workspace.scheduleSessionSave()
    }
    public func duplicate(_ id: UUID) {
        guard let source = tabs.first(where: { $0.id == id }) else { return }
        _ = newTab(url: source.url)
    }
    public func restoreClosed(_ id: UUID? = nil) {
        guard let index = (id == nil ? closedTabs.firstIndex(where: { $0.profileID == activeProfileID }) : closedTabs.firstIndex(where: { $0.id == id && $0.profileID == activeProfileID })) else { return }
        let item = closedTabs.remove(at: index)
        _ = newTab(url: item.url)
    }
    public func switchToNext(_ direction: Int) {
        guard !tabs.isEmpty, let id = selectedID, let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        select(tabs[(i + direction + tabs.count) % tabs.count].id)
    }

    public func navigateSelected(_ text: String, intelligence: Bool = false) {
        guard let selected else { return }
        navigate(selected, text: text, intelligence: intelligence)
    }
    public func navigate(_ tab: BrowserTab, text: String, intelligence: Bool = false) {
        AetherLatencyProbe.mark("ui.navigate.enter")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let direct = AddressResolver.directURL(trimmed)
        let remembered = direct == nil
            ? workspace.rememberedSite(for: trimmed, profileID: tab.profileID) : nil
        if direct == nil,
           remembered == nil,
           intelligence || workspace.preferences.provider.usesIntelligence {
            startJevSearch(tab, query: trimmed)
            return
        }
        guard let destination = direct ?? remembered ?? AddressResolver.resolve(
            text, provider: workspace.preferences.provider,
            locality: workspace.preferences.searchLocality,
            localityTerms: workspace.preferences.localityQueryTerms,
            customTemplate: workspace.preferences.customSearchTemplate) else { return }
        if tab.loadState == .loading, tab.pendingURL == destination.absoluteString { return }
        AetherLatencyProbe.mark("ui.resolve.end")
        tab.url = destination.absoluteString
        tab.pendingURL = destination.absoluteString
        tab.contentReady = false
        tab.paintReady = false
        tab.siteSurface = nil
        tab.sitePrefersDark = nil
        tab.loadState = .loading
        workspace.scheduleSessionSave()
        if tab.id == selectedID { beginNavigationGlow() }
        let epoch = beginNavigationEpoch(for: tab)
        navigationTasks[tab.id]?.cancel()
        navigationTasks[tab.id] = Task {
            do {
                let page: String
                if let existing = tab.enginePageID { page = existing }
                else {
                    page = try await workspace.engine.createPage(profileID: tab.profileID)
                    guard !Task.isCancelled, self.tabsByProfile[tab.profileID]?.contains(where: { $0.id == tab.id }) == true else {
                        await workspace.engine.close(pageID: page)
                        return
                    }
                    tab.enginePageID = page
                    enginePageIndex[page] = tab
                    AetherExtensions.shared.sync(self)
                }
                guard self.isCurrent(epoch, tab: tab) else { return }
                AetherLatencyProbe.mark("ui.page.created")
                if tab.id == self.selectedID,
                   let activating = workspace.engine as? any BrowserPageActivating {
                    try await activating.activate(pageID: page)
                }
                guard self.isCurrent(epoch, tab: tab) else { return }
                try await workspace.engine.navigate(pageID: page, url: destination)
                AetherLatencyProbe.mark("ui.navigate.dispatched")
                guard self.isCurrent(epoch, tab: tab) else { return }
                try await refresh(tab)

            } catch {
                self.fail(tab, error: error, epoch: epoch)
            }
        }
    }

    public func navigateExtension(_ tab: BrowserTab, to destination: URL) {
        guard ["https", "http", "chrome-extension"].contains(destination.scheme?.lowercased() ?? ""),
              destination.user == nil,
              tabsByProfile[tab.profileID]?.contains(where: { $0.id == tab.id }) == true else { return }
        tab.url = destination.absoluteString
        tab.pendingURL = destination.absoluteString
        tab.contentReady = false
        tab.paintReady = false
        tab.siteSurface = nil
        tab.sitePrefersDark = nil
        tab.loadState = .loading
        workspace.scheduleSessionSave()
        if tab.id == selectedID { beginNavigationGlow() }
        let epoch = beginNavigationEpoch(for: tab)
        navigationTasks[tab.id]?.cancel()
        navigationTasks[tab.id] = Task {
            do {
                let page: String
                if let existing = tab.enginePageID {
                    page = existing
                } else {
                    page = try await workspace.engine.createPage(profileID: tab.profileID)
                    guard !Task.isCancelled,
                          tabsByProfile[tab.profileID]?.contains(where: { $0.id == tab.id }) == true else {
                        await workspace.engine.close(pageID: page)
                        return
                    }
                    tab.enginePageID = page
                    enginePageIndex[page] = tab
                    AetherExtensions.shared.sync(self)
                }
                guard isCurrent(epoch, tab: tab) else { return }
                if tab.id == selectedID,
                   let activating = workspace.engine as? any BrowserPageActivating {
                    try await activating.activate(pageID: page)
                }
                guard isCurrent(epoch, tab: tab) else { return }
                try await workspace.engine.navigate(pageID: page, url: destination)
                guard isCurrent(epoch, tab: tab) else { return }
                try await refresh(tab)
            } catch {
                fail(tab, error: error, epoch: epoch)
            }
        }
    }

    private func tab(forEnginePage id: String) -> BrowserTab? {
        if let tab = enginePageIndex[id], tab.enginePageID == id { return tab }
        guard let tab = tabsByProfile.values.lazy.flatMap({ $0 })
            .first(where: { $0.enginePageID == id }) else { return nil }
        enginePageIndex[id] = tab
        return tab
    }

    private func forgetEnginePage(_ id: String) { enginePageIndex.removeValue(forKey: id) }

    @discardableResult private func beginNavigationEpoch(for tab: BrowserTab) -> UInt64 {
        let epoch = (navigationEpochs[tab.id] ?? 0) + 1
        navigationEpochs[tab.id] = epoch
        return epoch
    }

    private func isCurrent(_ epoch: UInt64, tab: BrowserTab) -> Bool {
        navigationEpochs[tab.id] == epoch
    }

    private func fail(_ tab: BrowserTab, error: Error, epoch: UInt64) {
        guard isCurrent(epoch, tab: tab), !Self.isCancellation(error), !tab.contentReady else { return }
        tab.loadState = .failed(error.localizedDescription)
        if tab.id == selectedID { finishGlow(true) }
    }

    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    public func startJevSearch(_ tab: BrowserTab, query: String) {
        navigationTasks[tab.id]?.cancel()
        navigationTasks[tab.id] = nil
        _ = beginNavigationEpoch(for: tab)
        tab.title = query
        tab.siteSurface = nil
        tab.sitePrefersDark = nil
        tab.url = nil
        tab.pendingURL = nil
        tab.contentReady = false
        tab.canGoBack = false
        tab.canGoForward = false
        tab.loadProgress = 0
        tab.loadState = .search(query)
        if tab.id == selectedID { beginNavigationGlow() }
    }

    public func searchSignals(limit: Int = 240) -> [BrowserSearchSignal] {
        var signals: [BrowserSearchSignal] = []
        var seen = Set<String>()
        let now = Date().timeIntervalSince1970
        for tab in tabs {
            guard let url = tab.url, !url.isEmpty, seen.insert(url).inserted else { continue }
            signals.append(BrowserSearchSignal(kind: .openTab, title: tab.title, url: url,
                                               visits: 1, lastVisit: now))
        }
        for mark in workspace.bookmarks(for: activeProfileID) where seen.insert(mark.url).inserted {
            signals.append(BrowserSearchSignal(kind: .bookmark, title: mark.title, url: mark.url,
                                               visits: 1,
                                               lastVisit: mark.createdAt.timeIntervalSince1970))
        }
        for item in workspace.shortcuts where seen.insert(item.url).inserted {
            signals.append(BrowserSearchSignal(kind: .shortcut, title: item.name, url: item.url,
                                               visits: 1, lastVisit: 0))
        }
        for visit in workspace.history(for: activeProfileID, limit: limit)
        where seen.insert(visit.url).inserted {
            signals.append(BrowserSearchSignal(kind: .history, title: visit.title, url: visit.url,
                                               visits: 1,
                                               lastVisit: visit.visitedAt.timeIntervalSince1970))
        }
        return signals
    }

    public func refresh(_ tab: BrowserTab) async throws {
        guard let page = tab.enginePageID else { throw BrowserPortError.pageUnavailable }
        let state = try await workspace.engine.snapshot(pageID: page)
        apply(state, to: tab)
    }
    public func joinMeeting() {
        guard let pageID = selected?.enginePageID,
              let actions = workspace.engine as? any BrowserNativeSemanticActions else { return }
        Task { await actions.joinMeeting(pageID: pageID) }
    }
    public func beginNavigationGlow() {
        glow.begin()
    }
    private func finishGlow(_ failed: Bool) {
        guard glow.phase.isActive else { return }
        if failed { glow.fail() } else { glow.contentVisible() }
        glow.settle()
    }
    private func apply(_ state: EnginePageSnapshot, to tab: BrowserTab) {
        let oldTitle = tab.title
        let oldURL = tab.url
        let oldLoading = tab.isLoading
        defer {
            if oldTitle != tab.title || oldURL != tab.url || oldLoading != tab.isLoading {
                AetherExtensions.shared.sync(self)
            }
        }
        let semanticSignals = state.closed ? nil : state.semanticSignals
        if tab.semanticSignals != semanticSignals { tab.semanticSignals = semanticSignals }
        if case .search = tab.loadState { return }
        if state.isLoading, tab.loadState != .loading { tab.muteAppliedURL = nil }
        if state.closed {
            if let page = tab.enginePageID { forgetEnginePage(page) }
            tab.enginePageID = nil
            tab.pendingURL = nil
            tab.loadState = .failed("The engine page was closed.")
            if tab.id == selectedID { finishGlow(true) }
            return
        }
        let title = state.title.isEmpty ? (state.url ?? "New Tab") : state.title
        if tab.title != title { tab.title = title }
        if tab.canGoBack != state.canGoBack { tab.canGoBack = state.canGoBack }
        if tab.canGoForward != state.canGoForward { tab.canGoForward = state.canGoForward }
        if tab.isSecure != state.isSecure { tab.isSecure = state.isSecure }
        if tab.loadProgress != state.progress { tab.loadProgress = state.progress }
        if tab.isLoading != state.isLoading { tab.isLoading = state.isLoading }
        if tab.contentReady != state.contentReady { tab.contentReady = state.contentReady }
        if tab.paintReady != state.paintReady { tab.paintReady = state.paintReady }
        // An error only replaces the page when there is no usable document yet.
        // A rendered page must never be swapped for a stale or unrelated error
        // overlay.
        if let error = state.error, !state.contentReady {
            if tab.loadState != .failed(error) { tab.loadState = .failed(error) }
            if tab.id == selectedID { finishGlow(true) }
            return
        }
        if !state.contentReady {
            if !state.isLoading {
                if tab.pendingURL != nil { tab.pendingURL = nil }
                if tab.url != nil { tab.url = nil }
                if tab.title != "New Tab" { tab.title = "New Tab" }
                if tab.loadProgress != 0 { tab.loadProgress = 0 }
                if tab.loadState != .newTab { tab.loadState = .newTab }
                if tab.id == selectedID {
                    glow.settle()
                }
                return
            }
            if tab.loadState != .loading { tab.loadState = .loading }
            if tab.pendingURL == nil {
                if tab.url != state.url { tab.siteSurface = nil; tab.sitePrefersDark = nil }
                if tab.url != state.url { tab.url = state.url }
            }
            if tab.id == selectedID, glow.phase == .started { glow.awaitContent() }
            return
        }
        if tab.pendingURL != nil { tab.pendingURL = nil }
        if tab.url != state.url { tab.siteSurface = nil; tab.sitePrefersDark = nil }
        if tab.url != state.url { tab.url = state.url }
        // Two signals end the progress indicator, both from the page itself:
        // the first paint (content is on screen while subresources continue)
        // and WebKit's own end of loading. A document that never reports paint
        // therefore stops loading when its load ends instead of hanging.
        let contentVisible = tab.paintReady || !state.isLoading
        guard contentVisible else {
            if tab.loadState != .loading { tab.loadState = .loading }
            if tab.id == selectedID, glow.phase == .started { glow.awaitContent() }
            return
        }
        if tab.loadState != .ready { tab.loadState = .ready }
        if tab.isMuted, tab.muteAppliedURL != state.url {
            applyAudioMute(tab)
            tab.muteAppliedURL = state.url
        }
        if tab.id == selectedID { finishGlow(false) }
        applySiteCustomizations(tab)
        if let url = state.url, lastNavigationURLs[state.id] != url {
            lastNavigationURLs[state.id] = url
            // Search-port: private tabs never touch history.
            guard !tab.isPrivateTab else { return }
            let visitID = workspace.recordVisit(profileID: tab.profileID, title: tab.title, url: url)
            if !workspace.isIncognito(tab.profileID),
               let provider = workspace.engine as? any BrowserPageTextProviding {
                let profileID = tab.profileID
                Task { [weak self] in
                    guard let text = try? await provider.indexablePageText(pageID: state.id),
                          let self, self.lastNavigationURLs[state.id] == url else { return }
                    self.workspace.updateVisitExcerpt(visitID, profileID: profileID, text: text)
                }
            }
        }
    }
    /// Search-port: per-site veil CSS + per-site zoom, applied live when ready.
    private func applySiteCustomizations(_ tab: BrowserTab) {
        guard let pageID = tab.enginePageID,
              let raw = tab.url, let url = URL(string: raw) else { return }
        let host = url.host?.lowercased()
        let zoom = zoomForHost(host)
        if abs(zoom - 1.0) > 0.01,
           let webView = workspace.engine.surface(pageID: pageID) as? WKWebView {
            webView.setValue(zoom, forKey: "pageZoom")
        }
        let css = VeilStore.shared.css(on: host.flatMap { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 })
        guard !css.isEmpty,
              let webView = workspace.engine.surface(pageID: pageID) as? WKWebView else { return }
        let escaped = css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
        webView.evaluateJavaScript("""
        (() => {
          const id = '__aetherVeils';
          let el = document.getElementById(id);
          if (!el) { el = document.createElement('style'); el.id = id; document.documentElement.appendChild(el); }
          el.textContent = `\(escaped)`;
        })();
        """, completionHandler: nil)
    }
    public func closeWindow() {
        observation?.cancel()
        for task in navigationTasks.values { task.cancel() }
        for tab in tabsByProfile.values.flatMap({ $0 }) {
            if let page = tab.enginePageID {
                surfaces.release(page)
                Task { await workspace.engine.close(pageID: page) }
            }
        }
        workspace.removeWindow(id)
        workspace.flushSession()
    }
    public func perform(_ action: EngineNavigationAction) {
        guard let tab = selected, let page = tab.enginePageID else { return }
        let epoch = beginNavigationEpoch(for: tab)
        if case .stop = action {
            navigationTasks[tab.id]?.cancel()
            if glow.phase.isActive { glow.fail(); glow.settle() }
        } else {
            beginNavigationGlow()
            tab.paintReady = false
            tab.loadState = .loading
        }
        navigationTasks[tab.id] = Task {
            do {
                switch action {
                case .back: try await workspace.engine.goBack(pageID: page)
                case .forward: try await workspace.engine.goForward(pageID: page)
                case .reload: try await workspace.engine.reload(pageID: page)
                case .stop: try await workspace.engine.stop(pageID: page)
                }
                guard self.isCurrent(epoch, tab: tab) else { return }
                try await refresh(tab)
            } catch {
                self.fail(tab, error: error, epoch: epoch)
            }
        }
    }
    public func setArrangement(_ mode: TabArrangement) { workspace.preferences.arrangement = mode }
    public func toggleArrangement() { setArrangement(arrangement == .top ? .sidebar : .top) }

    public func toggleHistoryPanel() {
        let shouldShow = !showsHistory
        showsTabSearch = false
        showsBookmarks = false
        showsHistory = shouldShow
    }

    public func toggleBookmarksPanel() {
        let shouldShow = !showsBookmarks
        showsTabSearch = false
        showsHistory = false
        showsBookmarks = shouldShow
    }

    public func showHistoryPanel() {
        showsTabSearch = false
        showsBookmarks = false
        showsHistory = true
    }

    public func showBookmarksPanel() {
        showsTabSearch = false
        showsHistory = false
        showsBookmarks = true
    }

    public func closeMenus() {
        showsProfileMenu = false
        showsMoreMenu = false
        showsExtensionsMenu = false
        showsJevSignals = false
    }
    public func toggleSidebar() {
        if arrangement != .sidebar {
            setArrangement(.sidebar)
            sidebarCollapsed = false
            return
        }
        sidebarCollapsed.toggle()
    }

    public func toggleFloatingVideo() {
        if floatingPageID != nil { landVideo(); return }
        guard let selected else { return }
        floatVideo(from: selected, requireSelection: true, quietly: false)
    }

    private func floatVideo(from tab: BrowserTab, requireSelection: Bool, quietly: Bool) {
        guard let pageID = tab.enginePageID,
              let webView = workspace.engine.surface(pageID: pageID) as? WKWebView,
              floatingPageID == nil,
              !quietly || Self.isKnownVideoSite(tab.url) else { return }
        webView.evaluateJavaScript(Isolate.on) { [weak self, weak webView] result, _ in
            guard let self, let webView, result as? String == "floating",
                  self.floatingPageID == nil, self.tab(forEnginePage: pageID) != nil,
                  !requireSelection || self.selected?.enginePageID == pageID else { return }
            self.floatingPageID = pageID
            self.floater.onClose = { [weak self] in self?.landVideo() }
            self.floater.onReturn = { [weak self] in
                guard let self else { return }
                self.landVideo()
                if let tab = self.tab(forEnginePage: pageID) { self.select(tab.id) }
                NSApp.activate(ignoringOtherApps: true)
                self.nativeWindow?.makeKeyAndOrderFront(nil)
            }
            self.floater.onSkip = { [weak webView] seconds in
                webView?.evaluateJavaScript(Isolate.skip(seconds)) { _, _ in }
            }
            self.floater.onPlayPause = { [weak webView] answer in
                webView?.evaluateJavaScript(Isolate.toggle) { result, _ in
                    answer(result as? Bool ?? true)
                }
            }
            self.floater.onProgress = { [weak webView] answer in
                webView?.evaluateJavaScript(Isolate.where_) { result, _ in
                    let values = result as? [Any] ?? []
                    answer(values.first as? Double ?? 0, values.dropFirst().first as? Bool ?? true)
                }
            }
            self.floater.lift(webView)
        }
    }

    public func landVideo() {
        guard let pageID = floatingPageID else { return }
        if let webView = workspace.engine.surface(pageID: pageID) as? WKWebView {
            webView.evaluateJavaScript(Isolate.off) { _, _ in }
        }
        floater.drop()
        floatingPageID = nil
    }
}

public enum EngineNavigationAction { case back, forward, reload, stop }
