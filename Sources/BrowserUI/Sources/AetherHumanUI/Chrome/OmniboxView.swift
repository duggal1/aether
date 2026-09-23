import AppKit
import SwiftUI

public struct OmniboxView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var focused = false
    @BrowserState private var draft = ""
    @BrowserState private var resignNonce = 0
    @BrowserState private var progressP = 0.0
    @BrowserState private var progressOpacity = 0.0
    @BrowserState private var progressNonce = 0
    @Namespace private var glassNS
    let window: BrowserWindowModel

    public init(window: BrowserWindowModel) { self.window = window }

    private var showsSuggestions: Bool {
        focused && !draft.isEmpty && window.suggestions.showsRows
    }

    private var appearance: AetherChromeAppearance {
        chrome ?? (theme.dark ? .dark : .light)
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            BrowserIconView(icon: focused ? .search : (window.selected?.isSecure == false ? .warning : .lock),
                            tint: focused ? appearance.text : appearance.icon)
                .iconSize(12)
                .frame(width: 16, height: 20, alignment: .center)
                .offset(y: -0.3)
            NativeAddressField(text: $draft, focused: $focused,
                textColor: appearance.text, placeholderColor: appearance.icon,
                fullAddress: window.selected?.url ?? "",
                placeholder: "Search \(window.workspace.preferences.provider.rawValue) or enter URL",
                focusRequest: window.addressFocusNonce,
                resignRequest: resignNonce,
                onSubmit: { commit($0) },
                onEscape: {
                    window.suggestions.dismiss()
                    draft = displayAddress(window.selected?.url)
                    endEditing()
                },
                onMove: { delta in
                    guard focused, window.suggestions.showsRows else { return }
                    window.suggestions.move(delta)
                },
                onComplete: { completeInline() })
                .frame(maxWidth: .infinity)
                .frame(height: 20, alignment: .center)
                .pointerStyle(.horizontalText)
                .onChange(of: draft) { _, value in
                    window.suggestions.update(prefix: value, window: window)
                }
                .onChange(of: focused) { _, now in
                    if now { window.suggestions.warm(profileID: window.activeProfileID, window: window) }
                    else {
                        window.suggestions.dismiss()
                        draft = displayAddress(window.selected?.url)
                    }
                }
                .onChange(of: window.selectedID) { _, _ in
                    window.suggestions.dismiss()
                    draft = displayAddress(window.selected?.url)
                    endEditing()
                }
                .onChange(of: window.selected?.url) { _, url in
                    if focused { endEditing() }
                    draft = displayAddress(url)
                }
                .onChange(of: window.workspace.preferences.provider) { _, _ in
                    guard focused else { return }
                    window.suggestions.update(prefix: draft, window: window)
                }
                .onChange(of: window.selected?.loadState == .loading) { _, loading in
                    if loading == true { startProgress() } else { finishProgress() }
                }
                .onChange(of: window.selectedID) { _, _ in
                    if isLoadingNow() { startProgress(); trackRealProgress() }
                }
                .onChange(of: window.selected?.loadProgress) { _, _ in trackRealProgress() }
            if !focused {
                Button { window.navigateSelected(SearchProvider.googleAI.homepage.absoluteString) } label: {
                    Text("AI Mode").font(AetherType.body(11)).foregroundStyle(appearance.icon)
                }
                .buttonStyle(.plain)
                .aetherPointingCursor()
                .aetherFocusTreatment(radius: 6)
                .focusEffectDisabled()
                .help("Open Google AI Mode")
                .accessibilityIdentifier("aether.google-ai")
            }
            Button {
                if let url = window.selected?.url {
                    let rawTitle = window.selected?.title ?? url
                    let title = (rawTitle.isEmpty || rawTitle == "New Tab")
                        ? (URL(string: url)?.host ?? url) : rawTitle
                    window.workspace.toggleBookmark(profileID: window.activeProfileID, title: title, url: url)
                }
            } label: {
                BrowserIconView(icon: window.workspace.isBookmarked(window.selected?.url, profileID: window.activeProfileID) ? .doubleBookmark : .bookmark,
                                tint: appearance.icon)
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
                .fill(appearance.addressBG)
        }
        .modifier(DiaProgressEffect(p: progressP, opacity: progressOpacity, focused: focused,
                                    trio: window.workspace.preferences.progressColor.gradientTrio))
        .animation(AetherMotion.focus(reduced), value: focused)
        .animation(AetherMotion.dropdown(reduced), value: showsSuggestions)
        .onAppear { draft = displayAddress(window.selected?.url) }
        .overlay(alignment: .topLeading) {
            if showsSuggestions {
                OmniboxSuggestionsView(model: window.suggestions, prefix: draft,
                                       provider: window.workspace.preferences.provider) { row in
                    choose(row)
                }
            }
        }
    }

    private func displayAddress(_ url: String?) -> String {
        guard let url else { return "" }
        if window.workspace.preferences.showFullAddress { return url }
        guard let host = URL(string: url)?.host, !host.isEmpty else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func endEditing() {
        if focused { focused = false }
        resignNonce += 1
    }

    private func completeInline() {
        guard focused, let completion = window.suggestions.completionText else { return }
        draft = completion
        window.suggestions.update(prefix: completion, window: window)
    }

    private func commit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let remembered = window.workspace.rememberedSite(for: trimmed, profileID: window.activeProfileID)
        let selected = window.suggestions.selectedRow
        if let target = OmniboxSuggestionBuilder.commitTarget(draft: trimmed, selected: selected, rememberedSite: remembered) {
            if let selected, selected.kind == .tab, selected.url == target, selected.tabID != nil {
                choose(selected)
                return
            }
            if let selected, selected.url == target {
                choose(selected)
                return
            }
            if selected?.kind == .open, selected?.url == nil, AddressResolver.directURL(trimmed) == nil, remembered == nil {
                if let row = selected {
                    choose(row)
                    return
                }
            }
            endEditing()
            window.suggestions.dismiss()
            draft = displayAddress(AddressResolver.directURL(target)?.absoluteString ?? target)
            window.navigateSelected(target)
            return
        }
        if text == draft, let row = selected {
            choose(row)
            return
        }
        endEditing()
        window.suggestions.dismiss()
        window.navigateSelected(trimmed)
    }

    private func choose(_ row: OmniboxSuggestion) {
        window.suggestions.record(row, profileID: window.activeProfileID)
        let destination: String?
        switch row.kind {
        case .tab:
            if let id = row.tabID { window.select(id) }
            endEditing()
            window.suggestions.dismiss()
            return
        case .open, .completion:
            destination = row.url ?? row.completionText
        case .bookmark, .history:
            destination = row.url ?? row.completionText ?? draft
        }
        guard let target = destination, !target.isEmpty else {
            endEditing()
            window.suggestions.dismiss()
            return
        }
        if let url = row.url { draft = displayAddress(url) }
        endEditing()
        window.suggestions.dismiss()
        window.navigateSelected(target)
    }

    private func isLoadingNow() -> Bool { window.selected?.loadState == .loading }

    private func startProgress() {
        progressNonce += 1
        if reduced {
            progressOpacity = 1
            progressP = 0.06
            return
        }
        withAnimation(.easeOut(duration: 0.14)) { progressOpacity = 1 }
        withAnimation(.smooth(duration: 0.18)) { progressP = 0.06 }
    }

    private func trackRealProgress() {
        guard isLoadingNow(), !reduced else { return }
        let real = min(1, max(0, window.selected?.loadProgress ?? 0))
        guard real > 0 else { return }
        let target = max(0.08, real)
        guard target > progressP - 0.001 else { return }
        withAnimation(.linear(duration: 0.18)) { progressP = target }
    }

    private func finishProgress() {
        guard progressOpacity > 0 || progressP > 0 else { return }
        progressNonce += 1
        let nonce = progressNonce
        withAnimation(.linear(duration: 0.12)) { progressP = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.13))
            guard !Task.isCancelled, nonce == progressNonce else { return }
            progressOpacity = 0
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

private func neutralProgress(_ deep: UInt, _ mid: UInt, _ pale: UInt) -> (UInt, UInt, UInt) {
    (deep, mid, pale)
}

private struct DiaProgressLayers: View {
    let p: Double
    let width: CGFloat
    let height: CGFloat
    let focused: Bool
    let trio: (UInt, UInt, UInt)

    private var deep: Color { Color(hex: trio.0) }
    private var mid: Color { Color(hex: trio.1) }
    private var pale: Color { Color(hex: trio.2) }

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: deep.opacity(0.72), location: 0),
                .init(color: mid.opacity(0.85), location: 0.52),
                .init(color: pale.opacity(0.62), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: max(2, width * CGFloat(min(1, max(0, p)))), height: 1)
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0),
                        .init(color: .black, location: 0.91),
                        .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
