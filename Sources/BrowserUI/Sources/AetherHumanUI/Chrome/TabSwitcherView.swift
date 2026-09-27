import SwiftUI

// Ported from Search Cmd+K switcher (TabBar switcher by name).
// Fuzzy filter over displayTitle + url, Enter selects, Esc closes.
public struct TabSwitcherView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var query = ""
    @FocusState private var focused: Bool
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var matches: [BrowserTab] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return window.tabs }
        return window.tabs.filter {
            $0.displayTitle.lowercased().contains(q) || ($0.url?.lowercased().contains(q) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                BrowserIconView(icon: .search, tint: theme.muted).iconSize(14)
                TextField("Switch to tab…", text: $query)
                    .textFieldStyle(.plain)
                    .font(AetherType.body(13))
                    .focused($focused)
                    .onSubmit { if let first = matches.first { window.select(first.id); window.showsTabSwitcher = false } }
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches.prefix(20)) { tab in
                        Button {
                            window.select(tab.id)
                            window.showsTabSwitcher = false
                        } label: {
                            HStack(spacing: 8) {
                                DomainIcon(tab.url, size: 14)
                                Text(tab.displayTitle.isEmpty ? "New Tab" : tab.displayTitle)
                                    .font(AetherType.body(12)).lineLimit(1)
                                    .foregroundStyle(theme.ink)
                                Spacer(minLength: 0)
                                if tab.isSleeping { Text("sleeping").font(AetherType.body(10)).foregroundStyle(theme.muted) }
                                if tab.isPrivateTab { Text("private").font(AetherType.body(10)).foregroundStyle(theme.muted) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                    if matches.isEmpty {
                        Text("No matching tabs")
                            .font(AetherType.body(12)).foregroundStyle(theme.muted)
                            .padding(14)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 420)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 24, y: 8)
        .onAppear { focused = true }
    }
}
