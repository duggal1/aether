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
                    searchSkeletons
                        .padding(.top, 14)
                } else if let failure {
                    AetherEmptyState(icon: .warning, heading: "Search unavailable", description: failure)
                        .padding(.top, 60)
                } else if let outcome, outcome.candidates.isEmpty {
                    AetherEmptyState(icon: .search, heading: "No results", description: "Jev found nothing relevant for “\(query)”.")
                        .padding(.top, 60)
                } else if let outcome {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(outcome.candidates) { candidate in
                            row(candidate)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .task(id: query) { await load() }
        .animation(AetherMotion.dropdown(reduced), value: outcome?.candidates.count ?? 0)
    }

    private var searchSkeletons: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                TerminalLoader()
                Text("Searching").font(AetherType.emphasis(13)).foregroundStyle(theme.muted)
            }
            .padding(.bottom, 8)
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.selected).frame(width: 270, height: 11)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.hover).frame(width: 170, height: 9)
                }
                .padding(.horizontal, 17)
                .frame(maxWidth: .infinity, minHeight: 69, alignment: .leading)
.background(theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .accessibilityLabel("Searching")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                BrowserIconView(icon: .search, tint: theme.muted).iconSize(13)
                Text(query).font(AetherType.panelTitle(17)).tracking(AetherTracking.heading).foregroundStyle(theme.heading)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background { JevQueryBarBackground() }
            HStack(spacing: 7) {
                if let outcome {
                    AetherBadge(outcome.degraded ? "Search limited" : label(outcome), variant: outcome.degraded ? .rose : .sky)
                        .id("verdict-\(label(outcome))-\(outcome.degraded)")
                        .transition(.opacity)
                    if outcome.retrievalCount > 0 {
                        AetherBadge("\(outcome.retrievalCount) retrieved", variant: .green)
                            .id("retrieved-\(outcome.retrievalCount)")
                            .transition(.opacity)
                    }
                    if let model = outcome.model {
                        AetherBadge(model, variant: .sky)
                            .id("model-\(model)")
                            .transition(.opacity)
                    }
                } else {
                    AetherBadge("Jev search", variant: .orange)
                }
            }
            .animation(AetherMotion.textResolve(reduced), value: badgeKey(outcome))
            if let outcome, outcome.degraded {
                Text("Jev could not judge this query. Add your API keys in Settings › Search Intelligence for full search intelligence.")
                    .font(AetherType.body(12)).foregroundStyle(theme.error)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 14)
    }

    private func label(_ outcome: BrowserSearchOutcome) -> String {
        let percent = Int((max(0, min(1, outcome.confidence)) * 100).rounded())
        return "\(outcome.intent) · \(percent)%"
    }

    private func badgeKey(_ outcome: BrowserSearchOutcome?) -> String {
        guard let outcome else { return "none" }
        return "\(label(outcome))|\(outcome.degraded)|\(outcome.retrievalCount)|\(outcome.model ?? "")"
    }

    private func row(_ candidate: BrowserSearchCandidate) -> some View {
        Button { open(candidate) } label: {
            HStack(alignment: .top, spacing: 10) {
                DomainIcon(candidate.kind == .google ? "https://www.google.com/" : candidate.url, size: 21)
                    .frame(width: 22, height: 22, alignment: .center)
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
                    AetherBadge(reason(candidate.kind), variant: candidate.kind == .web ? .green : .sky)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        outcome = nil
        failure = nil
        do {
            // The pipeline judges local candidates against the query; handed an
            // empty list it could only ever return web results, so the whole
            // local tier of the ranking was unreachable in the app.
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
