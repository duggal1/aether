import SwiftUI

public struct OmniboxView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var focused = false
    @BrowserState private var draft = ""
    @BrowserState private var selection = 0
    @BrowserState private var showingSuggestions = false
    @BrowserState private var progressP = 0.0
    @BrowserState private var progressOpacity = 0.0
    @BrowserState private var loadCycle = 0
    @Namespace private var glassNS
    let window: BrowserWindowModel

    public init(window: BrowserWindowModel) { self.window = window }

    private var matches: [OmniboxResult] {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var items: [OmniboxResult] = []
        for tab in window.tabs where tab.title.localizedCaseInsensitiveContains(query) || (tab.url?.localizedCaseInsensitiveContains(query) == true) {
            items.append(OmniboxResult(id: tab.id, title: tab.title, subtitle: tab.url ?? "", kind: .tab, url: tab.url))
        }
        for item in window.workspace.bookmarks(for: window.activeProfileID) where item.title.localizedCaseInsensitiveContains(query) || item.url.localizedCaseInsensitiveContains(query) {
            items.append(OmniboxResult(id: item.id, title: item.title, subtitle: item.url, kind: .bookmark, url: item.url))
        }
        for item in window.workspace.visits where item.profileID == window.activeProfileID && (item.title.localizedCaseInsensitiveContains(query) || item.url.localizedCaseInsensitiveContains(query)) {
            if !items.contains(where: { $0.url == item.url }) {
                items.append(OmniboxResult(id: item.id, title: item.title, subtitle: item.url, kind: .history, url: item.url))
            }
        }
        return Array(items.prefix(7))
    }

    public var body: some View {
        HStack(spacing: 8) {
            BrowserIconView(icon: focused ? .search : (window.selected?.isSecure == false ? .warning : .lock),
                            tint: focused ? theme.ink : theme.muted)
                .iconSize(12)
                .frame(height: 20, alignment: .center)
            NativeAddressField(text: $draft, focused: $focused,
                fullAddress: window.selected?.url ?? "",
                placeholder: "Search \(window.workspace.preferences.provider.rawValue) or enter URL",
                focusRequest: window.addressFocusNonce,
                onSubmit: { commit() }, onEscape: { showingSuggestions = false })
                .frame(maxWidth: .infinity)
                .pointerStyle(.horizontalText)
                .onChange(of: draft) { _, _ in
                    showingSuggestions = focused && !draft.isEmpty && draft != window.selected?.url
                    selection = 0
                }
                .onChange(of: focused) { _, now in
                    if !now { draft = displayAddress(window.selected?.url); showingSuggestions = false }
                }
                .onChange(of: window.selectedID) { _, _ in
                    draft = displayAddress(window.selected?.url); showingSuggestions = false
                }
                .onChange(of: window.selected?.url) { _, url in
                    if !focused { draft = displayAddress(url) }
                }
                .onChange(of: window.selected?.loadState == .loading) { _, loading in
                    if loading == true { startProgress() } else { finishProgress() }
                }
            if !focused {
                Button { window.navigateSelected("https://www.google.com/ai") } label: {
                    Text("AI Mode").font(AetherType.body(11)).foregroundStyle(theme.muted)
                }
                .buttonStyle(.plain)
                .aetherFocusTreatment(radius: 6)
                .focusEffectDisabled()
                .help("Open Google AI Mode")
                .accessibilityIdentifier("aether.google-ai")
            }
            if focused && !draft.isEmpty {
                Button { draft = "" } label: {
                    BrowserIconView(icon: .close, tint: theme.muted).iconSize(11)
                }
                .buttonStyle(.plain)
                .aetherFocusTreatment(radius: 6)
                .focusEffectDisabled()
                .help("Clear address")
            }
            Button {
                if let url = window.selected?.url {
                    window.workspace.toggleBookmark(profileID: window.activeProfileID, title: window.selected?.title ?? url, url: url)
                }
            } label: {
                BrowserIconView(icon: window.workspace.isBookmarked(window.selected?.url, profileID: window.activeProfileID) ? .doubleBookmark : .bookmark,
                                tint: theme.muted)
                    .iconSize(13)
            }
            .buttonStyle(.plain)
            .aetherFocusTreatment(radius: 6)
            .focusEffectDisabled()
            .help("Bookmark this page")
        }
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(height: 30)
        .background {
            if focused || progressOpacity > 0 {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.hover.opacity(0.55))
            }
        }
        .modifier(DiaProgressEffect(p: progressP, opacity: progressOpacity,
                                    color: window.workspace.preferences.progressColor.color))
        .animation(AetherMotion.focus(reduced), value: focused)
        .animation(.snappy(duration: 0.16), value: showingSuggestions)
        .onAppear { draft = displayAddress(window.selected?.url) }
        .overlay(alignment: .topLeading) {
            AetherGlassGroup(spacing: 8) {
                if showingSuggestions { suggestions }
            }
        }
    }

    private var suggestions: some View {
        VStack(spacing: 2) {
            suggestionRow(offset: 0, selected: selection == 0) {
                HStack(spacing: 9) {
                    BrowserIconView(icon: .search, tint: theme.muted).iconSize(12)
                    Text("Search or open \"\(draft)\"").lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\u{21A9}").foregroundStyle(theme.soft)
                }
            } action: { commit() }
            ForEach(Array(matches.enumerated()), id: \.element.id) { offset, item in
                suggestionRow(offset: offset + 1, selected: selection == offset + 1) {
                    HStack(spacing: 10) {
                        DomainIcon(item.url, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(AetherType.rowTitle(12)).lineLimit(1)
                            Text(item.subtitle).font(AetherType.caption(11)).foregroundStyle(theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                    }
                } action: { choose(item) }
            }
        }
        .padding(6)
        .frame(maxWidth: 470)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            AetherPopoverBackground()
                .aetherGlassMorph("aether.omni.suggestions", in: glassNS, transition: .materialize)
        }
        .aetherGlassShadow(dark: theme.dark)
        .offset(y: 38)
        .zIndex(2)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    @ViewBuilder private func suggestionRow<Content: View>(offset: Int, selected: Bool, @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .font(AetherType.body(12))
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherFocusTreatment(radius: 8)
        .focusEffectDisabled()
        .aetherPointingCursor()
    }

    private func displayAddress(_ url: String?) -> String {
        guard let url else { return "" }
        if window.workspace.preferences.showFullAddress { return url }
        return URL(string: url)?.host ?? url
    }
    private func commit() {
        if selection > 0 && selection <= matches.count { choose(matches[selection - 1]); return }
        let text = draft
        focused = false; showingSuggestions = false
        window.navigateSelected(text)
    }
    private func choose(_ item: OmniboxResult) {
        focused = false; showingSuggestions = false
        if item.kind == .tab { window.select(item.id) }
        else if let url = item.url { window.navigateSelected(url) }
    }

    private func startProgress() {
        loadCycle += 1
        if reduced {
            progressOpacity = 1
            progressP = 0.10
        } else {
            withAnimation(.easeOut(duration: 0.1)) { progressOpacity = 1 }
            progressP = 0
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18)) { progressP = 0.10 }
        }
    }

    private func finishProgress() {
        guard progressOpacity > 0 || progressP > 0 else { return }
        loadCycle += 1
        let cycle = loadCycle
        if reduced {
            progressP = 1
            progressP = 0
            withAnimation(.easeIn(duration: 0.3)) { progressOpacity = 0 }
        } else {
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.2)) { progressP = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.35))
                guard loadCycle == cycle else { return }
                withAnimation(.easeIn(duration: 0.3)) { progressOpacity = 0 }
                try? await Task.sleep(for: .seconds(0.32))
                guard loadCycle == cycle else { return }
                progressP = 0
            }
        }
    }
}

private struct DiaProgressEffect: AnimatableModifier {
    var p: Double
    var opacity: Double
    var color: Color

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(p, opacity) }
        set { p = newValue.first; opacity = newValue.second }
    }

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                DiaProgressLayers(p: p, width: proxy.size.width, height: proxy.size.height, color: color)
            }
            .opacity(opacity)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct DiaProgressLayers: View {
    let p: Double
    let width: Double
    let height: Double
    let color: Color

    private var head: Double { min(1, max(0.10, p)) * width }
    private var t: Double { min(1, max(0, (1 - p) / 0.9)) }
    private var mid: Double { t + (1 - t) * 0.5 }

    private func pastHead(_ delta: Double, factor: Double) -> Gradient.Stop {
        Gradient.Stop(color: color.opacity(0.78 * factor), location: stopLocation(head + delta))
    }

    private func stopLocation(_ x: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, x / width))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            core.frame(height: 0.5)
            rim.frame(height: 0.5)
        }
        .frame(width: width, height: height, alignment: .leading)
        .overlay(alignment: .topLeading) { glow }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var glow: some View {
        LinearGradient(stops: [
            Gradient.Stop(color: color.opacity(0.78 * t), location: 0),
            Gradient.Stop(color: color.opacity(0.78 * mid), location: stopLocation(head * 0.5)),
            Gradient.Stop(color: color.opacity(0.78), location: stopLocation(head)),
            pastHead(5, factor: 0.78),
            pastHead(10, factor: 0.61),
            pastHead(20, factor: 0.43),
            pastHead(30, factor: 0.30),
            pastHead(40, factor: 0.22),
            pastHead(60, factor: 0.17),
            pastHead(80, factor: 0.13),
            pastHead(120, factor: 0.09),
            pastHead(220, factor: 0),
        ], startPoint: .leading, endPoint: .trailing)
        .frame(width: width, height: height)
        .mask {
            LinearGradient(stops: [
                Gradient.Stop(color: .black.opacity(0.07), location: 0),
                Gradient.Stop(color: .black.opacity(0.075), location: 0.10),
                Gradient.Stop(color: .black.opacity(0.09), location: 0.233),
                Gradient.Stop(color: .black.opacity(0.10), location: 0.367),
                Gradient.Stop(color: .black.opacity(0.11), location: 0.50),
                Gradient.Stop(color: .black.opacity(0.13), location: 0.567),
                Gradient.Stop(color: .black.opacity(0.15), location: 0.633),
                Gradient.Stop(color: .black.opacity(0.17), location: 0.70),
                Gradient.Stop(color: .black.opacity(0.20), location: 0.767),
                Gradient.Stop(color: .black.opacity(0.25), location: 0.833),
                Gradient.Stop(color: .black.opacity(0.35), location: 0.90),
                Gradient.Stop(color: .black.opacity(0.49), location: 0.95),
                Gradient.Stop(color: .black.opacity(0.49), location: 0.967),
                Gradient.Stop(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    private var core: some View {
        let span = head + 1.5
        return LinearGradient(stops: [
            Gradient.Stop(color: color.opacity(0.78 * t), location: 0),
            Gradient.Stop(color: color.opacity(0.78 * mid), location: span > 0 ? min(1, head * 0.5 / span) : 0),
            Gradient.Stop(color: color.opacity(0.78), location: span > 0 ? min(1, head / span) : 0),
            Gradient.Stop(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
        .frame(width: span)
    }

    private var rim: some View {
        ZStack {
            LinearGradient(stops: [
                Gradient.Stop(color: color.opacity(0.9 * t), location: 0),
                Gradient.Stop(color: color.opacity(0.9 * mid), location: stopLocation(head * 0.5)),
                Gradient.Stop(color: color.opacity(0.9), location: stopLocation(head)),
                Gradient.Stop(color: .clear, location: stopLocation(head + 1.5)),
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [
                Gradient.Stop(color: .white.opacity(0.35 * t), location: 0),
                Gradient.Stop(color: .white.opacity(0.35), location: stopLocation(head)),
                Gradient.Stop(color: .clear, location: stopLocation(head + 1.5)),
            ], startPoint: .leading, endPoint: .trailing)
        }
        .frame(width: head + 1.5)
    }
}

private struct OmniboxResult: Identifiable {
    enum Kind {
        case tab, bookmark, history
        var icon: BrowserIcon {
            switch self { case .tab: .web; case .bookmark: .bookmark; case .history: .history }
        }
    }
    var id: UUID
    var title: String
    var subtitle: String
    var kind: Kind
    var url: String?
}
