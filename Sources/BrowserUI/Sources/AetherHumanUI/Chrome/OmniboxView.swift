import AppKit
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
        HStack(alignment: .center, spacing: 8) {
            BrowserIconView(icon: focused ? .search : (window.selected?.isSecure == false ? .warning : .lock),
                            tint: focused ? theme.ink : theme.muted)
                .iconSize(12)
                .frame(width: 16, height: 20, alignment: .center)
            NativeAddressField(text: $draft, focused: $focused,
                fullAddress: window.selected?.url ?? "",
                placeholder: "Search \(window.workspace.preferences.provider.rawValue) or enter URL",
                focusRequest: window.addressFocusNonce,
                onSubmit: { commit() }, onEscape: { showingSuggestions = false },
                onMove: { delta in
                    guard focused else { return }
                    if !showingSuggestions, !draft.isEmpty { showingSuggestions = true }
                    selection = min(matches.count, max(0, selection + delta))
                })
                .frame(maxWidth: .infinity)
                .frame(height: 20, alignment: .center)
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
                .onChange(of: window.selectedID) { _, _ in
                    if isLoadingNow() { startProgress(); trackRealProgress() }
                }
                .onChange(of: window.selected?.loadProgress) { _, _ in trackRealProgress() }
            if !focused {
                Button { window.navigateSelected("https://www.google.com/ai") } label: {
                    Text("AI Mode").font(AetherType.body(11)).foregroundStyle(theme.muted)
                }
                .buttonStyle(.plain)
                .aetherPointingCursor()
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
                .aetherPointingCursor()
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
            .aetherPointingCursor()
            .aetherFocusTreatment(radius: 6)
            .focusEffectDisabled()
            .help("Bookmark this page")
        }
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.omnibox)
        }
        .modifier(DiaProgressEffect(p: progressP, opacity: progressOpacity, focused: focused,
                                    trio: window.workspace.preferences.progressColor.gradientTrio))
        .animation(AetherMotion.focus(reduced), value: focused)
        .animation(AetherMotion.dropdown(reduced), value: showingSuggestions)
        .onAppear { draft = displayAddress(window.selected?.url) }
        .overlay(alignment: .topLeading) {
            if showingSuggestions { suggestions }
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.composer)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.faintLine, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .aetherFloatingShadow(dark: theme.dark)
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
                .background(selected ? theme.suggestionSelected : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherFocusTreatment(radius: 7)
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

    private func isLoadingNow() -> Bool { window.selected?.loadState == .loading }

    private func startProgress() {
        loadCycle += 1
        if reduced {
            progressOpacity = 1
            progressP = 0.14
            return
        }
        withAnimation(.easeOut(duration: 0.12)) { progressOpacity = 1 }
        withAnimation(.timingCurve(0.34, 0.08, 0.4, 1, duration: 0.28)) { progressP = 0.14 }
        withAnimation(.linear(duration: 6).delay(0.22)) { progressP = 0.18 }
    }

    private func trackRealProgress() {
        guard isLoadingNow(), !reduced else { return }
        let real = min(1, max(0, window.selected?.loadProgress ?? 0))
        guard real > 0 else { return }
        loadCycle += 1
        let target = max(0.08, real)
        guard target > progressP - 0.001 else { return }
        withAnimation(.linear(duration: 0.18)) { progressP = target }
    }

    private func finishProgress() {
        guard progressOpacity > 0 || progressP > 0 else { return }
        loadCycle += 1
        let cycle = loadCycle
        let tabID = window.selectedID
        if reduced {
            progressP = 0
            progressOpacity = 0
            return
        }
        withAnimation(.easeOut(duration: 0.22)) { progressP = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.24))
            guard loadCycle == cycle, window.selectedID == tabID, !isLoadingNow() else { return }
            withAnimation(.easeIn(duration: 0.3)) { progressOpacity = 0 }
            try? await Task.sleep(for: .seconds(0.32))
            guard loadCycle == cycle, window.selectedID == tabID, !isLoadingNow() else { return }
            progressP = 0
        }
    }
}

private struct DiaProgressEffect: AnimatableModifier {
    var p: Double
    var opacity: Double
    var focused: Bool
    var trio: (UInt, UInt, UInt)

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(p, opacity) }
        set { p = newValue.first; opacity = newValue.second }
    }

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                DiaProgressLayers(p: p, width: proxy.size.width, height: proxy.size.height,
                                  focused: focused, trio: trio)
            }
            .opacity(opacity)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private extension Color {
    init(hex: UInt) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }

    func blended(with other: Color, by amount: Double) -> Color {
        let t = min(1, max(0, amount))
        #if os(macOS)
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB,
                     red: Double(a.redComponent) + (Double(b.redComponent) - Double(a.redComponent)) * t,
                     green: Double(a.greenComponent) + (Double(b.greenComponent) - Double(a.greenComponent)) * t,
                     blue: Double(a.blueComponent) + (Double(b.blueComponent) - Double(a.blueComponent)) * t,
                     opacity: 1)
        #else
        return t < 0.5 ? self : other
        #endif
    }
}

private struct DiaProgressLayers: View {
    let p: Double
    let width: Double
    let height: Double
    let focused: Bool
    let trio: (UInt, UInt, UInt)

    private var deep: Color { Color(hex: trio.0) }
    private var mid: Color { Color(hex: trio.1) }
    private var pale: Color { Color(hex: trio.2) }

    private var fill: Double { 0.05 + 0.90 * min(1, max(0, p)) }

    private func spanColor(_ s: Double) -> Color {
        if s <= 0.20 { return deep }
        if s <= 0.50 {
            let u = (s - 0.20) / 0.30
            return deep.blended(with: mid, by: AetherSmoothGradient.smootherstep(u))
        }
        if s <= 0.72 {
            let u = (s - 0.50) / 0.22
            return mid.blended(with: pale, by: AetherSmoothGradient.smootherstep(u))
        }
        return pale
    }

    private func editorialStops(peak: Double) -> [Gradient.Stop] {
        let steps = 64
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(steps + 1)
        for index in 0...steps {
            let u = Double(index) / Double(steps)
            if u <= fill {
                let s = min(1, max(0, (u - 0.05) / 0.90))
                let edge = AetherSmoothGradient.smootherstep(min(1, s / 0.10))
                    * (1 - AetherSmoothGradient.smootherstep(max(0, (s - 0.90) / 0.10)))
                stops.append(Gradient.Stop(color: spanColor(s).opacity(peak * edge), location: u))
            } else {
                let tail = min(1, (u - fill) / max(0.001, 1 - fill))
                let alpha = peak * pow(1 - AetherSmoothGradient.smootherstep(tail), 2.2)
                stops.append(Gradient.Stop(color: pale.opacity(alpha), location: u))
            }
        }
        return stops
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(stops: editorialStops(peak: 1), startPoint: .leading, endPoint: .trailing)
                .frame(width: width, height: 11)
                .blur(radius: 10)
                .opacity(focused ? 0.48 : 0.28)
                .mask {
                    LinearGradient(stops: [
                        Gradient.Stop(color: .clear, location: 0),
                        Gradient.Stop(color: .black, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            LinearGradient(stops: editorialStops(peak: 1), startPoint: .leading, endPoint: .trailing)
                .frame(width: width, height: 2)
                .blur(radius: focused ? 1 : 1.5)
                .opacity(focused ? 0.95 : 0.65)
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .animation(.easeOut(duration: 0.28), value: focused)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
