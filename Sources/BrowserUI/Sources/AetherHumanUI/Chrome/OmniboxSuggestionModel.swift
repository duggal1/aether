import Foundation
import Observation

@MainActor @Observable
public final class OmniboxSuggestionModel {
    public private(set) var rows: [OmniboxSuggestion] = []
    public private(set) var selected = 0
    public private(set) var isFetching = false

    public var showsRows: Bool { !rows.isEmpty }

    @ObservationIgnored private var prefix = ""
    @ObservationIgnored private var previousPrefix = ""
    @ObservationIgnored private var completions: [String] = []
    @ObservationIgnored private var suggestedSites: [OmniboxSuggestion] = []
    @ObservationIgnored private var rankedHistory: [UUID] = []
    @ObservationIgnored private var forceIntelligence = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var intelligenceTask: Task<Void, Never>?
    @ObservationIgnored private var nativeTask: Task<Void, Never>?
    @ObservationIgnored private var accepted: [String: Int] = [:]
    @ObservationIgnored private var acceptedProfile: UUID?
    @ObservationIgnored private let acceptedDefaults: UserDefaults

    static let debounce = Duration.milliseconds(180)
    static let completionLimit = 9

    public init(acceptedDefaults: UserDefaults = .standard) {
        self.acceptedDefaults = acceptedDefaults
    }

    public var selectedRow: OmniboxSuggestion? {
        guard selected >= 0, selected < rows.count else { return nil }
        return rows[selected]
    }

    public var completionText: String? {
        guard let row = selectedRow, let completion = row.completionText else { return nil }
        return completion
    }

    public func update(prefix raw: String, window: BrowserWindowModel,
                       forceIntelligence: Bool = false) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = trimmed != prefix || self.forceIntelligence != forceIntelligence
            || acceptedProfile != window.activeProfileID
        if changed {
            previousPrefix = prefix
            prefix = trimmed
            self.forceIntelligence = forceIntelligence
            generation += 1
            fetchTask?.cancel()
            intelligenceTask?.cancel()
            nativeTask?.cancel()
            fetchTask = nil
            intelligenceTask = nil
            nativeTask = nil
            isFetching = false
            selected = 0
            if trimmed.isEmpty || !trimmed.hasPrefix(previousPrefix) { completions = [] }
            suggestedSites = []
            rankedHistory = []
        }
        loadAccepted(profileID: window.activeProfileID)
        rebuild(window: window)
        guard changed, !trimmed.isEmpty, window.workspace.preferences.showSearchSuggestions else { return }
        if window.workspace.preferences.providerSuggestions {
            scheduleFetch(prefix: trimmed, window: window, token: generation)
        }
        if forceIntelligence || window.workspace.preferences.provider.usesIntelligence {
            scheduleIntelligence(prefix: trimmed, window: window, token: generation)
        }
        scheduleNative(prefix: trimmed, window: window, token: generation)
    }

    public func warm(profileID: UUID, window: BrowserWindowModel) {
        loadAccepted(profileID: profileID)
        guard window.workspace.preferences.showSearchSuggestions,
              window.workspace.preferences.providerSuggestions,
              let provider = window.workspace.engine as? any BrowserSearchSuggesting
        else { return }
        let endpoint = window.workspace.preferences.provider == .jev
            ? SearchProvider.google.endpoint : window.workspace.preferences.provider.endpoint
        Task { await provider.warmSearchCompletions(providerEndpoint: endpoint) }
    }

    public func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selected = min(rows.count - 1, max(0, selected + delta))
    }

    public func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selected = index
    }

    public func dismiss() {
        rows = []
        selected = 0
        fetchTask?.cancel()
        intelligenceTask?.cancel()
        nativeTask?.cancel()
        fetchTask = nil
        intelligenceTask = nil
        nativeTask = nil
        isFetching = false
        prefix = ""
        previousPrefix = ""
        completions = []
        suggestedSites = []
        rankedHistory = []
        forceIntelligence = false
        generation += 1
    }

    public func record(_ row: OmniboxSuggestion, profileID: UUID) {
        loadAccepted(profileID: profileID)
        guard row.kind != .open else { return }
        accepted[row.title.lowercased(), default: 0] += 1
        if !prefix.isEmpty { accepted["#" + prefix.lowercased(), default: 0] += 1 }
        if accepted.count > 400 {
            let pruned = accepted.sorted { $0.value > $1.value }.prefix(200)
            accepted = Dictionary(uniqueKeysWithValues: pruned.map { ($0.key, $0.value) })
        }
        guard let profileID = acceptedProfile else { return }
        acceptedDefaults.set(accepted, forKey: Self.acceptedKey(profileID))
    }

    private func scheduleFetch(prefix: String, window: BrowserWindowModel, token: Int) {
        guard let provider = window.workspace.engine as? any BrowserSearchSuggesting else { return }
        let selectedProvider = window.workspace.preferences.provider
        let endpoint = forceIntelligence || selectedProvider == .jev
            ? SearchProvider.google.endpoint : selectedProvider.endpoint
        isFetching = true
        fetchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let fetched = (try? await provider.searchCompletions(
                prefix: prefix, limit: Self.completionLimit, providerEndpoint: endpoint)) ?? []
            guard !Task.isCancelled, let self, token == self.generation else { return }
            self.isFetching = false
            guard !fetched.isEmpty else { return }
            self.completions = fetched
            self.rebuild(window: window)
        }
    }

    private func scheduleIntelligence(prefix: String, window: BrowserWindowModel, token: Int) {
        guard let provider = window.workspace.engine as? any BrowserSearchIntelligence else { return }
        intelligenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let candidates = (try? await provider.jevCompletions(
                prefix: prefix, local: window.searchSignals(limit: 48), limit: 3)) ?? []
            guard !Task.isCancelled, let self, token == self.generation else { return }
            self.suggestedSites = candidates.compactMap { candidate in
                guard candidate.kind == .navigate, let address = candidate.url,
                      let url = URL(string: address),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, url.user == nil else { return nil }
                return OmniboxSuggestion(kind: .open, title: "Open \(host)", host: host,
                                         url: address, matched: prefix.count, score: 390)
            }
            self.rebuild(window: window)
        }
    }

    private func scheduleNative(prefix: String, window: BrowserWindowModel, token: Int) {
        guard prefix.count >= 3,
              let provider = window.workspace.engine as? any BrowserNativeSearchIntelligence
        else { return }
        let terms = prefix.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var scored: [(visit: BrowserVisit, hits: Int)] = []
        for visit in window.workspace.history(for: window.activeProfileID, limit: 300) {
            guard let excerpt = visit.excerpt else { continue }
            let content = (visit.title + " " + visit.url + " " + excerpt).lowercased()
            let hits = terms.filter { content.contains($0) }.count
            scored.append((visit, hits))
        }
        scored.sort { left, right in
            left.hits == right.hits ? left.visit.visitedAt > right.visit.visitedAt
                : left.hits > right.hits
        }
        let pages = scored.prefix(24).map { entry in
            BrowserSearchMemory(id: entry.visit.id, title: entry.visit.title,
                                url: entry.visit.url, excerpt: entry.visit.excerpt ?? "")
        }
        guard !pages.isEmpty else { return }
        nativeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let ranked = await provider.rankHistory(query: prefix, pages: pages)
            guard !Task.isCancelled, let self, token == self.generation else { return }
            self.rankedHistory = ranked
            self.rebuild(window: window)
        }
    }

    private func rebuild(window: BrowserWindowModel) {
        let provider = forceIntelligence ? SearchProvider.jev : window.workspace.preferences.provider
        guard window.workspace.preferences.showSearchSuggestions, !prefix.isEmpty else {
            rows = []
            selected = 0
            return
        }
        let tabs = window.tabs.map {
            OmniboxTabSource(id: $0.id, title: $0.title, url: $0.url)
        }
        rows = OmniboxSuggestionBuilder.rows(
            prefix: prefix, provider: provider, tabs: tabs,
            bookmarks: window.workspace.bookmarks(for: window.activeProfileID),
            visits: window.workspace.visits.filter { $0.profileID == window.activeProfileID },
            completions: completions, accepted: accepted,
            rememberedSite: window.workspace.rememberedSite(for: prefix,
                                                             profileID: window.activeProfileID),
            suggestedSites: suggestedSites, rankedHistory: rankedHistory)
        selected = min(selected, max(0, rows.count - 1))
    }

    private func loadAccepted(profileID: UUID) {
        guard acceptedProfile != profileID else { return }
        acceptedProfile = profileID
        accepted = acceptedDefaults.dictionary(forKey: Self.acceptedKey(profileID)) as? [String: Int] ?? [:]
    }

    private static func acceptedKey(_ profileID: UUID) -> String {
        "aether.suggest.accepted." + profileID.uuidString
    }
}
