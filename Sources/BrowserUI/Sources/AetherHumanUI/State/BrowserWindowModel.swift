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
    public var showsDownloads = false
    public var showsInspector = false
    public var showsReader = false
    public var showsFind = false
    public var showsSettings = false
    public var findQuery = ""
    public var addressFocusNonce = 0
    public var alert: String?
    public private(set) var glow = AetherNavigationGlowState()
    @ObservationIgnored private var glowSettleTask: Task<Void, Never>?
    @ObservationIgnored private var navigationTasks: [UUID: Task<Void, Never>] = [:]
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
        if let observing = workspace.engine as? any BrowserPageObserving {
            let updates = observing.pageUpdates()
            observation = Task { [weak self] in
                for await state in updates {
                    guard let self, !Task.isCancelled else { return }
                    for tab in self.tabsByProfile.values.flatMap({ $0 }) where tab.enginePageID == state.id {
                        self.apply(state, to: tab)
                    }
                }
            }
        }
    }
    public func restoreProfile() async {
        guard !restorationStarted, workspace.preferences.restoreWindows,
              let provider = workspace.engine as? any BrowserProfileManaging else { return }
        restorationStarted = true
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
    public func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectionByProfile[activeProfileID] = id
    }
    @discardableResult public func newTab(url: String? = nil) -> BrowserTab {
        let tab = BrowserTab(profileID: activeProfileID)
        tabsByProfile[activeProfileID, default: []].append(tab)
        selectionByProfile[activeProfileID] = tab.id
        if let url { navigate(tab, text: url) }
        return tab
    }
    public func switchProfile(_ id: UUID) {
        guard workspace.profiles.contains(where: { $0.id == id }) else { return }
        let leavingIncognito = isIncognito && activeProfileID != id
        activeProfileID = id
        if tabsByProfile[id, default: []].isEmpty { _ = newTab() }
        isIncognito = workspace.isIncognito(id)
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
        closedTabs.insert(ClosedTab(title: tab.title, url: tab.url, profileID: tab.profileID), at: 0)
        if closedTabs.count > 30 { closedTabs.removeLast() }
        if let page = tab.enginePageID { surfaces.release(page); Task { await workspace.engine.close(pageID: page) } }
        tabsByProfile[activeProfileID]?.remove(at: current)
        if selectedID == id {
            let remaining = tabs
            selectionByProfile[activeProfileID] = remaining.isEmpty ? nil : remaining[min(current, remaining.count - 1)].id
        }
        if tabs.isEmpty { _ = newTab() }
    }
    public func closeOthers(_ id: UUID) {
        for tab in tabs where tab.id != id && !tab.isPinned { close(tab.id) }
    }
    public func togglePin(_ id: UUID) { tabs.first(where: { $0.id == id })?.isPinned.toggle() }
    public func moveTab(_ source: UUID, before target: UUID) {
        guard var items = tabsByProfile[activeProfileID], let from = items.firstIndex(where: { $0.id == source }),
              let to = items.firstIndex(where: { $0.id == target }), from != to else { return }
        let moved = items.remove(at: from)
        items.insert(moved, at: min(to, items.count))
        tabsByProfile[activeProfileID] = items
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

    public func navigateSelected(_ text: String) {
        guard let selected else { return }
        navigate(selected, text: text)
    }
    public func navigate(_ tab: BrowserTab, text: String) {
        guard let destination = AddressResolver.resolve(text, provider: workspace.preferences.provider) else { return }
        tab.url = destination.absoluteString
        tab.loadState = .loading
        if tab.id == selectedID { beginNavigationGlow() }
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
                try await workspace.engine.navigate(pageID: page, url: destination)
                try await refresh(tab)

            } catch {
                guard !Task.isCancelled else { return }
                tab.loadState = .failed(error.localizedDescription)
            }
        }
    }
    public func refresh(_ tab: BrowserTab) async throws {
        guard let page = tab.enginePageID else { throw BrowserPortError.pageUnavailable }
        let state = try await workspace.engine.snapshot(pageID: page)
        apply(state, to: tab)
    }
    public func beginNavigationGlow() {
        glowSettleTask?.cancel()
        glowSettleTask = nil
        glow.begin()
    }
    private func finishGlow(_ failed: Bool) {
        guard glow.phase.isActive else { return }
        if failed { glow.fail() } else { glow.contentVisible() }
        scheduleGlowSettle(after: failed ? 0.28 : 0.38)
    }
    private func scheduleGlowSettle(after delay: TimeInterval) {
        glowSettleTask?.cancel()
        glowSettleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.glow.settle()
        }
    }
    private func apply(_ state: EnginePageSnapshot, to tab: BrowserTab) {
        if state.closed {
            tab.enginePageID = nil
            tab.loadState = .failed("The engine page was closed.")
            if tab.id == selectedID { finishGlow(true) }
            return
        }
        tab.title = state.title.isEmpty ? (state.url ?? "New Tab") : state.title
        tab.url = state.url
        tab.canGoBack = state.canGoBack
        tab.canGoForward = state.canGoForward
        tab.isSecure = state.isSecure
        tab.loadProgress = state.progress
        if let error = state.error {
            tab.loadState = .failed(error)
            if tab.id == selectedID { finishGlow(true) }
        } else if state.isLoading {
            tab.loadState = .loading
            if tab.id == selectedID, glow.phase == .started { glow.awaitContent() }
        } else {
            tab.loadState = .ready
            if tab.id == selectedID { finishGlow(false) }
        }
        if !state.isLoading, state.error == nil, let url = state.url,
           lastNavigationURLs[state.id] != url {
            lastNavigationURLs[state.id] = url
            workspace.recordVisit(profileID: tab.profileID, title: tab.title, url: url)
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
    }
    public func perform(_ action: EngineNavigationAction) {
        guard let tab = selected, let page = tab.enginePageID else { return }
        if case .stop = action {
            navigationTasks[tab.id]?.cancel()
            if glow.phase.isActive { glow.fail(); scheduleGlowSettle(after: 0.24) }
        } else {
            beginNavigationGlow()
        }
        tab.loadState = .loading
        Task {
            do {
                switch action {
                case .back: try await workspace.engine.goBack(pageID: page)
                case .forward: try await workspace.engine.goForward(pageID: page)
                case .reload: try await workspace.engine.reload(pageID: page)
                case .stop: try await workspace.engine.stop(pageID: page)
                }
                try await refresh(tab)
            } catch { tab.loadState = .failed(error.localizedDescription) }
        }
    }
    public func setArrangement(_ mode: TabArrangement) { workspace.preferences.arrangement = mode }
    public func toggleArrangement() { setArrangement(arrangement == .top ? .sidebar : .top) }

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
