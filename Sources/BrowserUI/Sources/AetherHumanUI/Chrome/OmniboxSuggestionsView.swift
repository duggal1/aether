import SwiftUI

public struct OmniboxSuggestionsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
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
                                     onHoverSelect: { model.select(index) }) {
                    onChoose(row)
                }
                .id(row.id)
            }
        }
        .padding(9)
        .frame(maxWidth: 656)
        .background {
            AetherSuggestionBackground()
        }
        .offset(y: 37)
        .zIndex(2)
        .transition(.opacity)
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
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    let row: OmniboxSuggestion
    let prefix: String
    let provider: SearchProvider
    let selected: Bool
    let onHoverSelect: () -> Void
    let action: () -> Void

    private var appearance: AetherChromeAppearance { chrome ?? (theme.dark ? .dark : .light) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                leading
                title
                Spacer(minLength: 6)
                trailing
            }
            .font(AetherType.body(13))
            .foregroundStyle(appearance.text)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { AetherInteractionSurface(active: selected || hovering, radius: 6, selected: selected, hovering: hovering) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherFocusTreatment(radius: 7)
        .focusEffectDisabled()
        .aetherPointingCursor()
        .animation(AetherMotion.textResolve(reduced), value: row.title)
        .animation(AetherMotion.dropdown(reduced), value: selected)
        // Hover only highlights. It must never move the keyboard selection, or
        // Enter would commit whatever the pointer happens to rest on instead of
        // the address the user typed.
        .onHover { inside in
            hovering = inside
            if inside { onHoverSelect() }
        }
        .accessibilityIdentifier("aether.suggestion.\(row.kind.rawValue)")
    }

    @ViewBuilder private var leading: some View {
        switch row.kind {
        case .open:
            DomainIcon(row.url ?? provider.homepage.absoluteString, size: 18)
                .frame(width: 18, alignment: .center)
        case .completion:
            BrowserIconView(icon: .search, tint: appearance.secondary)
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
                .id("title-\(row.title)")
                .transition(.opacity)
        }
    }

    private var completionTitle: some View {
        let match = min(row.matched, row.title.count)
        let head = String(row.title.prefix(match))
        let tail = String(row.title.dropFirst(match))
        return HStack(spacing: 0) {
            Text(head).foregroundColor(appearance.text)
            Text(tail).foregroundColor(appearance.secondary)
        }
            .lineLimit(1)
            .truncationMode(.tail)
            .id("completion-\(row.title)")
            .transition(.opacity)
    }

    @ViewBuilder private var trailing: some View {
        switch row.kind {
        case .completion:
            if selected { Image(systemName: "return").font(AetherType.symbol(12)).foregroundStyle(appearance.secondary) }
        case .tab, .bookmark, .history:
            HStack(spacing: 7) {
                if let host = row.host, !row.title.localizedCaseInsensitiveContains(host) {
                    Text(host)
                        .font(AetherType.caption(11))
                        .foregroundStyle(appearance.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .id("host-\(host)")
                        .transition(.opacity)
                }
                if selected {
                    Image(systemName: "return").font(AetherType.symbol(12)).foregroundStyle(appearance.secondary)
                } else {
                    BrowserIconView(icon: kindIcon, tint: appearance.secondary).iconSize(13)
                }
            }
        case .open:
            if selected { Image(systemName: "return").font(AetherType.symbol(12)).foregroundStyle(appearance.secondary) }
        }
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
            .font(AetherType.data(10))
            .foregroundStyle(theme.soft)
    }
}
