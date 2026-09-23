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
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var accepted: [String: Int] = [:]
    @ObservationIgnored private var acceptedProfile: UUID?
    @ObservationIgnored private let acceptedDefaults: UserDefaults

    static let debounce = Duration.milliseconds(30)
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

    public func update(prefix raw: String, window: BrowserWindowModel) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = trimmed != prefix
        if changed {
            previousPrefix = prefix
            prefix = trimmed
            generation += 1
            fetchTask?.cancel()
            fetchTask = nil
            isFetching = false
            selected = 0
            if trimmed.isEmpty || !trimmed.hasPrefix(previousPrefix) { completions = [] }
        }
        loadAccepted(profileID: window.activeProfileID)
        rebuild(window: window)
        guard changed, !trimmed.isEmpty, window.workspace.preferences.showSearchSuggestions
        else { return }
        guard window.workspace.preferences.providerSuggestions else {
            completions = []
            rebuild(window: window)
            return
        }
        scheduleFetch(prefix: trimmed, window: window, token: generation)
    }

    public func warm(profileID: UUID, window: BrowserWindowModel) {
        loadAccepted(profileID: profileID)
        guard window.workspace.preferences.showSearchSuggestions,
              window.workspace.preferences.providerSuggestions,
              let provider = window.workspace.engine as? any BrowserSearchSuggesting
        else { return }
        let endpoint = window.workspace.preferences.provider.endpoint
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
        fetchTask = nil
        isFetching = false
        prefix = ""
        previousPrefix = ""
        completions = []
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
        let endpoint = window.workspace.preferences.provider.endpoint
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

    private func rebuild(window: BrowserWindowModel) {
        let provider = window.workspace.preferences.provider
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
                                                             profileID: window.activeProfileID))
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
