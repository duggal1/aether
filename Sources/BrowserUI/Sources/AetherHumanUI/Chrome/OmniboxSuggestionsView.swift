import SwiftUI

public struct OmniboxSuggestionsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let model: OmniboxSuggestionModel
    let prefix: String
    let provider: SearchProvider
    let onChoose: (OmniboxSuggestion) -> Void

    public init(model: OmniboxSuggestionModel, prefix: String, provider: SearchProvider,
                onChoose: @escaping (OmniboxSuggestion) -> Void) {
        self.model = model
        self.prefix = prefix
        self.provider = provider
        self.onChoose = onChoose
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                if index == separatorIndex { gap }
                OmniboxSuggestionRow(row: row, prefix: prefix, provider: provider,
                                     selected: model.selected == index,
                                     onHover: { model.select(index) }) {
                    onChoose(row)
                }
                .id(row.id)
            }
        }
        .padding(9)
        .frame(maxWidth: 656)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 0.5)
        }
            
        .offset(y: 37)
        .zIndex(2)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(AetherMotion.dropdown(reduced), value: model.rows.count)
    }

    private var separatorIndex: Int? {
        guard let completion = model.rows.firstIndex(where: { $0.kind == .completion }) else { return nil }
        let library = model.rows.firstIndex { $0.kind == .tab || $0.kind == .bookmark || $0.kind == .history }
        guard let library, library > completion, library > 1 else { return nil }
        return library
    }

    private var gap: some View {
        Color.clear.frame(height: 6)
    }
}

private struct OmniboxSuggestionRow: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    let row: OmniboxSuggestion
    let prefix: String
    let provider: SearchProvider
    let selected: Bool
    let onHover: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                leading
                title
                Spacer(minLength: 6)
                trailing
            }
            .font(AetherType.body(13))
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherFocusTreatment(radius: 7)
        .focusEffectDisabled()
        .aetherPointingCursor()
        .onHover { inside in
            guard inside else { return }
            onHover()
        }
        .accessibilityIdentifier("aether.suggestion.\(row.kind.rawValue)")
    }

    private var fill: Color {
        if selected { return theme.suggestionSelected }
        return hovering ? theme.hover : .clear
    }

    @ViewBuilder private var leading: some View {
        switch row.kind {
        case .open:
            DomainIcon(row.url ?? provider.homepage.absoluteString, size: 18)
                .frame(width: 18, alignment: .center)
        case .completion:
            BrowserIconView(icon: .search, tint: theme.muted)
                .iconSize(12)
                .frame(width: 16, alignment: .center)
        case .tab, .bookmark, .history:
            DomainIcon(row.url, size: 18)
                .frame(width: 16, alignment: .center)
        }
    }

    @ViewBuilder private var title: some View {
        switch row.kind {
        case .completion:
            completionTitle
        case .open where row.url == nil:
            completionTitle
        default:
            Text(row.title)
                .font(AetherType.rowTitle(12))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var completionTitle: some View {
        let match = min(row.matched, row.title.count)
        let head = String(row.title.prefix(match))
        let tail = String(row.title.dropFirst(match))
        return HStack(spacing: 0) {
            Text(head).foregroundColor(theme.ink)
            Text(tail).foregroundColor(theme.muted)
        }
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder private var trailing: some View {
        switch row.kind {
        case .completion:
            if selected { Image(systemName: "arrow.right").font(AetherType.symbol(13)).foregroundStyle(theme.muted) }
        case .tab, .bookmark, .history:
            HStack(spacing: 7) {
                if let host = row.host, !row.title.localizedCaseInsensitiveContains(host) {
                    Text(host)
                        .font(AetherType.caption(11))
                        .foregroundStyle(theme.soft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                BrowserIconView(icon: kindIcon, tint: theme.soft).iconSize(13)
            }
        case .open:
            EmptyView()
        }
        if selected, row.kind == .open { Image(systemName: "return").font(AetherType.symbol(12)).foregroundStyle(theme.muted) }
    }

    private var kindIcon: BrowserIcon {
        switch row.kind {
        case .tab: .web
        case .bookmark: .bookmark
        default: .history
        }
    }

    private func hint(_ glyph: String) -> some View {
        Text(glyph)
            .font(AetherType.mono(10))
            .foregroundStyle(theme.soft)
    }
}
