import SwiftUI

public struct JevSearchResultsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var outcome: BrowserSearchOutcome?
    @BrowserState private var failure: String?
    @BrowserState private var loading = false
    let query: String
    let window: BrowserWindowModel

    public init(query: String, window: BrowserWindowModel) {
        self.query = query
        self.window = window
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if loading && outcome == nil {
                    AetherEmptyState(icon: .search, heading: "Searching", description: "Jev is judging candidates for “\(query)”.")
                        .padding(.top, 60)
                } else if let failure {
                    AetherEmptyState(icon: .warning, heading: "Search unavailable", description: failure)
                        .padding(.top, 60)
                } else if let outcome, outcome.candidates.isEmpty {
                    AetherEmptyState(icon: .search, heading: "No results", description: "Jev found nothing relevant for “\(query)”.")
                        .padding(.top, 60)
                } else if let outcome {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(outcome.candidates) { candidate in
                            row(candidate)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .task(id: query) { await load() }
        .animation(AetherMotion.dropdown(reduced), value: outcome?.candidates.count ?? 0)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                BrowserIconView(icon: .search, tint: theme.muted).iconSize(13)
                Text(query).font(AetherType.panelTitle(17)).foregroundStyle(theme.heading)
            }
            HStack(spacing: 7) {
                if let outcome {
                    chip(label(outcome), tint: outcome.degraded ? theme.error : theme.muted)
                    if outcome.retrievalCount > 0 {
                        chip("\(outcome.retrievalCount) retrieved", tint: theme.muted)
                    }
                    if let model = outcome.model {
                        chip(model, tint: theme.soft)
                    }
                } else {
                    chip("Jev search", tint: theme.muted)
                }
            }
            if let outcome, outcome.degraded {
                Text("Jev could not judge this query. Add TYPESAFE_API_KEY and SEARCH1API_API_KEY to .env for full search intelligence.")
                    .font(AetherType.body(12)).foregroundStyle(theme.error)
            }
        }
        .padding(.bottom, 14)
    }

    private func label(_ outcome: BrowserSearchOutcome) -> String {
        let percent = Int((max(0, min(1, outcome.confidence)) * 100).rounded())
        return "\(outcome.intent) · \(percent)%"
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(AetherType.body(11))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(theme.raised, in: Capsule())
    }

    private func row(_ candidate: BrowserSearchCandidate) -> some View {
        Button { open(candidate) } label: {
            HStack(alignment: .top, spacing: 10) {
                BrowserIconView(icon: icon(candidate.kind), tint: theme.muted)
                    .iconSize(13)
                    .frame(width: 18, height: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.title)
                        .font(AetherType.body(13))
                        .foregroundStyle(theme.ink)
                        .lineLimit(2)
                    if !candidate.subtitle.isEmpty {
                        Text(candidate.subtitle)
                            .font(AetherType.body(11))
                            .foregroundStyle(theme.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
                if candidate.kind == .navigate || candidate.kind == .web
                    || candidate.kind == .google {
                    Text(reason(candidate.kind))
                        .font(AetherType.body(11))
                        .foregroundStyle(theme.soft)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .aetherPointingCursor()
    }

    private func icon(_ kind: BrowserSearchCandidateKind) -> BrowserIcon {
        switch kind {
        case .navigate, .completion: return .globe
        case .bookmark: return .bookmark
        case .history: return .history
        case .openTab: return .globe
        case .web: return .web
        case .google: return .search
        }
    }

    private func reason(_ kind: BrowserSearchCandidateKind) -> String {
        switch kind {
        case .navigate, .completion: return "Website"
        case .google: return "Google"
        case .web: return "Web"
        case .history, .bookmark, .openTab: return ""
        }
    }

    private func open(_ candidate: BrowserSearchCandidate) {
        guard let url = candidate.url else { return }
        window.navigateSelected(url)
    }

    private func load() async {
        guard let provider = window.workspace.engine as? any BrowserSearchIntelligence else {
            failure = "The browser engine is not connected."
            return
        }
        loading = true
        failure = nil
        do {
            let result = try await provider.jevSearch(query: query, local: window.searchSignals())
            guard !Task.isCancelled else { return }
            outcome = result
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
        loading = false
    }
}
