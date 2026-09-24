import Foundation
import Observation

@MainActor @Observable
public final class BrowserWindowModel: Identifiable {
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
    public var showsNewProfile = false
    public var showsRenameProfile = false
    public var showsDownloads = false
    public var showsInspector = false
    public var showsReader = false
    public var showsFind = false
    public var showsSettings = false
    public var findQuery = ""
    public var addressFocusNonce = 0
    public let suggestions = OmniboxSuggestionModel()
    public var alert: String?
    public private(set) var glow = AetherNavigationGlowState()
    @ObservationIgnored private var navigationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var navigationEpochs: [UUID: UInt64] = [:]
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var restorationStarted = false
    @ObservationIgnored private var lastNavigationURLs: [String: String] = [:]
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
        AetherLatencyProbe.mark("model.created")
        if let observing = workspace.engine as? any BrowserPageObserving {
            let updates = observing.pageUpdates()
            observation = Task { [weak self] in
                for await state in updates {
                    guard let self, !Task.isCancelled else { return }
                    if let tab = self.tabsByProfile.values.lazy.flatMap({ $0 })
                        .first(where: { $0.enginePageID == state.id }) {
                        self.apply(state, to: tab)
                    }
                }
            }
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
        closeMenus()
        selectionByProfile[activeProfileID] = id
        if let tab = tabs.first(where: { $0.id == id }), tab.needsRestoreLoad, let url = tab.url {
            tab.needsRestoreLoad = false
            navigate(tab, text: url)
        }
        workspace.scheduleSessionSave()
    }
    @discardableResult public func newTab(url: String? = nil) -> BrowserTab {
        closeMenus()
        let tab = BrowserTab(profileID: activeProfileID)
        tabsByProfile[activeProfileID, default: []].append(tab)
        selectionByProfile[activeProfileID] = tab.id
        if let url { navigate(tab, text: url) }
        workspace.scheduleSessionSave()
        return tab
    }
    public func switchProfile(_ id: UUID) {
        guard workspace.profiles.contains(where: { $0.id == id }) else { return }
        let leavingIncognito = isIncognito && activeProfileID != id
        activeProfileID = id
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
            if let page = tab.enginePageID { surfaces.release(page); Task { await workspace.engine.close(pageID: page) } }
        }
        tabsByProfile.removeValue(forKey: id)
        selectionByProfile.removeValue(forKey: id)
        closedTabs.removeAll { $0.profileID == id }
        if activeProfileID == id { switchProfile(next) }
    }
    public func close(_ id: UUID) {
        guard let current = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[current]
        navigationTasks.removeValue(forKey: id)?.cancel()
        if case .newTab = tab.loadState {
        } else if case .search = tab.loadState {
        } else if let url = tab.url, !url.isEmpty, url != "about:blank" {
            closedTabs.insert(ClosedTab(title: tab.title.isEmpty ? url : tab.title, url: tab.url, profileID: tab.profileID), at: 0)
            if closedTabs.count > 30 { closedTabs.removeLast() }
        }
        if let page = tab.enginePageID { surfaces.release(page); Task { await workspace.engine.close(pageID: page) } }
        tabsByProfile[activeProfileID]?.remove(at: current)
        if selectedID == id {
            let remaining = tabs
            selectionByProfile[activeProfileID] = remaining.isEmpty ? nil : remaining[min(current, remaining.count - 1)].id
        }
        if tabs.isEmpty { _ = newTab() }
        workspace.scheduleSessionSave()
    }
    public func closeOthers(_ id: UUID) {
        for tab in tabs where tab.id != id && !tab.isPinned { close(tab.id) }
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
            localityTerms: workspace.preferences.localityQueryTerms) else { return }
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
                }
                guard self.isCurrent(epoch, tab: tab) else { return }
                AetherLatencyProbe.mark("ui.page.created")
                try await workspace.engine.navigate(pageID: page, url: destination)
                AetherLatencyProbe.mark("ui.navigate.dispatched")
                guard self.isCurrent(epoch, tab: tab) else { return }
                try await refresh(tab)

            } catch {
                self.fail(tab, error: error, epoch: epoch)
            }
        }
    }

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
    public func beginNavigationGlow() {
        glow.begin()
    }
    private func finishGlow(_ failed: Bool) {
        guard glow.phase.isActive else { return }
        if failed { glow.fail() } else { glow.contentVisible() }
        glow.settle()
    }
    private func apply(_ state: EnginePageSnapshot, to tab: BrowserTab) {
        if case .search = tab.loadState { return }
        if state.closed {
            tab.enginePageID = nil
            tab.pendingURL = nil
            tab.loadState = .failed("The engine page was closed.")
            if tab.id == selectedID { finishGlow(true) }
            return
        }
        tab.title = state.title.isEmpty ? (state.url ?? "New Tab") : state.title
        tab.canGoBack = state.canGoBack
        tab.canGoForward = state.canGoForward
        tab.isSecure = state.isSecure
        tab.loadProgress = state.progress
        tab.isLoading = state.isLoading
        tab.contentReady = state.contentReady
        tab.paintReady = state.paintReady
        // An error only replaces the page when there is no usable document yet.
        // A rendered page must never be swapped for a stale or unrelated error
        // overlay.
        if let error = state.error, !state.contentReady {
            tab.loadState = .failed(error)
            if tab.id == selectedID { finishGlow(true) }
            return
        }
        if !state.contentReady {
            if !state.isLoading {
                tab.pendingURL = nil
                tab.url = nil
                tab.title = "New Tab"
                tab.loadProgress = 0
                tab.loadState = .newTab
                if tab.id == selectedID {
                    glow.settle()
                }
                return
            }
            tab.loadState = .loading
            if tab.pendingURL == nil {
                if tab.url != state.url { tab.siteSurface = nil; tab.sitePrefersDark = nil }
                tab.url = state.url
            }
            if tab.id == selectedID, glow.phase == .started { glow.awaitContent() }
            return
        }
        tab.pendingURL = nil
        if tab.url != state.url { tab.siteSurface = nil; tab.sitePrefersDark = nil }
        tab.url = state.url
        // Two signals end the progress indicator, both from the page itself:
        // the first paint (content is on screen while subresources continue)
        // and WebKit's own end of loading. A document that never reports paint
        // therefore stops loading when its load ends instead of hanging.
        let contentVisible = tab.paintReady || !state.isLoading
        guard contentVisible else {
            tab.loadState = .loading
            if tab.id == selectedID, glow.phase == .started { glow.awaitContent() }
            return
        }
        tab.loadState = .ready
        if tab.id == selectedID { finishGlow(false) }
        if let url = state.url, lastNavigationURLs[state.id] != url {
            lastNavigationURLs[state.id] = url
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

    public func closeMenus() {
        showsProfileMenu = false
        showsMoreMenu = false
    }
    public func toggleSidebar() {
        if arrangement != .sidebar {
            setArrangement(.sidebar)
            sidebarCollapsed = false
            return
        }
        sidebarCollapsed.toggle()
    }
}

public enum EngineNavigationAction { case back, forward, reload, stop }
