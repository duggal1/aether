import SwiftUI

public struct OmniboxSuggestionsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
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
                                     selected: model.selected == index) {
                    onChoose(row)
                }
                .id(row.id)
            }
        }
        .padding(9)
        .frame(maxWidth: 600)
        .background {
            AetherSuggestionBackground()
        }
        .offset(y: 37)
        .zIndex(2)
        .transition(AetherMotion.surfaceTransition(reduced, anchor: .top))
        .animation(AetherMotion.surfaceOpen(reduced), value: model.rows.count)
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
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    let row: OmniboxSuggestion
    let prefix: String
    let provider: SearchProvider
    let selected: Bool
    let action: () -> Void

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                leading
                title
                Spacer(minLength: 6)
                trailing
            }
            .font(AetherType.body(13))
            .foregroundStyle(skin.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    if selected {
                        // Apple Wi-Fi-menu style highlight: a subtle translucent
                        // fill over the blur, never a flat grey slab.
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(skin.selectionFill)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(skin.hoverFill)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherFocusTreatment(radius: 8)
        .focusEffectDisabled()
        .aetherPointingCursor()
        .animation(AetherMotion.selection(reduced), value: selected)
        // Hover only highlights. It must never move the keyboard selection, or
        // Enter would commit whatever the pointer happens to rest on instead of
        // the address the user typed.
        .onHover { inside in
            hovering = inside
        }
        .accessibilityIdentifier("aether.suggestion.\(row.kind.rawValue)")
    }

    @ViewBuilder private var leading: some View {
        switch row.kind {
        case .open:
            DomainIcon(row.url ?? provider.homepage.absoluteString, size: 18)
                .frame(width: 18, alignment: .center)
        case .completion:
            BrowserIconView(icon: .search, tint: skin.secondaryIcon)
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
            Text(head).foregroundColor(skin.primaryText)
            Text(tail).foregroundColor(skin.secondaryText)
        }
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder private var trailing: some View {
        switch row.kind {
        case .completion:
            if selected {
                Image(systemName: "return").font(AetherType.symbol(12)).foregroundStyle(skin.secondaryIcon)
            }
        case .tab, .bookmark, .history:
            HStack(spacing: 7) {
                if let host = row.host, !row.title.localizedCaseInsensitiveContains(host) {
                    Text(host)
                        .font(AetherType.caption(11))
                        .foregroundStyle(skin.metadataText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if selected {
                    Image(systemName: "return").font(AetherType.symbol(12)).foregroundStyle(skin.secondaryIcon)
                } else {
                    BrowserIconView(icon: kindIcon, tint: skin.secondaryIcon).iconSize(13)
                }
            }
        case .open:
            if selected {
                Image(systemName: "return").font(AetherType.symbol(12)).foregroundStyle(skin.secondaryIcon)
            }
        }
    }

    private var kindIcon: BrowserIcon {
        switch row.kind {
        case .tab: .web
        case .bookmark: .bookmark
        default: .history
        }
    }
}
