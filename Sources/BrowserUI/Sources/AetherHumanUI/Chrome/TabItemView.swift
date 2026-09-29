import SwiftUI
import UniformTypeIdentifiers

public struct TabItemView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var hovering = false
    @BrowserState private var showPreview = false
    @BrowserState private var hoverToken = 0
    @FocusState private var slotCloseFocused: Bool
    @FocusState private var trailCloseFocused: Bool
    let tab: BrowserTab
    let selected: Bool
    let compact: Bool
    let topFused: Bool
    let isFirst: Bool
    let window: BrowserWindowModel

    public init(tab: BrowserTab, selected: Bool, compact: Bool, window: BrowserWindowModel,
                topFused: Bool = false, isFirst: Bool = false) {
        self.tab = tab; self.selected = selected; self.compact = compact
        self.window = window; self.topFused = topFused; self.isFirst = isFirst
    }

    private var isNewTab: Bool {
        guard let url = tab.url, !url.isEmpty else { return true }
        return url == "about:blank"
    }

    private var closeTint: Color {
        if selected {
            if let chrome { return chrome.text.opacity(0.85) }
            return theme.dark ? AetherPalette.text(theme.dark).opacity(0.78) : Color(.sRGB, red: 0x1A / 255, green: 0x1B / 255, blue: 0x1F / 255, opacity: 1)
        }
        if let chrome { return chrome.secondary }
        return theme.dark ? AetherPalette.text(theme.dark).opacity(0.78) : theme.muted
    }

    private var truncationMask: some View {
        LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: 16)
    }

    @BrowserState private var renameText = ""
    private var tabTitleText: some View {
        Group {
            if window.renamingTabID == tab.id {
                TextField("Tab name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(AetherType.body(12))
                    .onSubmit { window.renameTab(tab.id, to: renameText); window.renamingTabID = nil }
                    .onExitCommand { window.renamingTabID = nil }
                    .onAppear { renameText = tab.customTitle.isEmpty ? tab.title : tab.customTitle }
            } else {
                Text(tab.displayTitle)
                    .font(AetherType.body(12))
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .foregroundStyle(titleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask {
                        HStack(spacing: 0) {
                            Rectangle().fill(.white)
                            truncationMask
                        }
                    }
                    .offset(y: topFused ? 0.35 : 0.3)
                    .opacity(tab.isSleeping ? 0.55 : 1.0)
            }
        }
    }

    private var titleColor: Color {
        if selected {
            if topFused {
                return chrome?.text ?? theme.ink
            }
            return chrome?.sidebarTitle ?? theme.ink
        }
        return chrome?.secondary ?? AetherPalette.tabTitle(theme.dark)
    }

    public var body: some View {
        Button { window.select(tab.id) } label: {
            HStack(spacing: compact ? 0 : 10) {
                ZStack {
                    if tab.loadState == .loading && (!topFused || compact) {
                        TerminalLoader().frame(width: 16, height: 16)
                    } else {
                        DomainIcon(tab.url, size: topFused ? 16 : 15,
                                   logoTint: chrome?.icon ?? theme.ink)
                            .frame(width: 16, alignment: .center)
                            .opacity(replacesFavicon && hovering ? 0 : 1)
                    }
                }
                .frame(maxWidth: compact ? .infinity : nil)
                if !compact {
                    tabTitleText
                }
                if tab.loadState == .loading && topFused && !compact {
                    TerminalLoader().frame(width: 16, height: 16)
                } else if tab.isPinned && !compact {
                    BrowserIconView(icon: .pin, tint: theme.soft).iconSize(10)
                        .frame(width: 16, alignment: .center)
                }
            }
            .padding(.horizontal, compact ? 2 : (topFused ? 8 : 10))
            // The close control is drawn beside this button rather than inside
            // it: a button nested in another button's label is never handed the
            // click on macOS, which is why the cross closed nothing. Its width
            // is held open here, so the title truncates in exactly the same
            // place it always did — nothing about the row's look changes.
            .padding(.trailing, compact ? 0 : closeWidthReserve)
            .frame(height: topFused ? AetherMetrics.tabHeight : 32)
            .background {
                selectionBackground
                    .animation(AetherMotion.tab(reduced), value: selected)
            }
            .overlay(alignment: .bottomLeading) {
                // Search-port: reading-progress grey fill, throttled by engine updates.
                if tab.loadState == .loading && tab.loadProgress > 0.02 && tab.loadProgress < 0.999 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(theme.muted.opacity(selected ? 0.35 : 0.25))
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, tab.loadProgress))), height: 2)
                    }
                    .frame(height: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !compact else { return }
                window.renamingTabID = tab.id
            }
        }
        .buttonStyle(.plain)
        .aetherPointingCursor()
        .focusEffectDisabled()
        .animation(AetherMotion.hover(reduced), value: hovering)
        .onHover { value in
            hovering = value
            hoverToken += 1
            let token = hoverToken
            if value, !topFused, !compact {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.4))
                    if hovering, hoverToken == token { showPreview = true }
                }
            } else {
                showPreview = false
            }
        }
        .overlay(alignment: .topLeading) {
            if showPreview, !topFused, !compact {
                SidebarHoverPreview(tab: tab, isNewTab: isNewTab)
                    .offset(x: sidebarWidth + 2, y: -8)
                    .zIndex(30)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        // One close control, used by both rows: the trailing one in the sidebar
        // and the wide tab strip, and the one that takes the favicon's place in
        // the narrow strip. Both are siblings of the row button, so both are
        // real targets.
        .overlay(alignment: .trailing) {
            if !compact {
                closeControl(focused: $trailCloseFocused)
                    .padding(.trailing, horizontalPadding)
                    .opacity(hovering || trailCloseFocused ? 1 : 0)
                    .allowsHitTesting(hovering || trailCloseFocused)
            }
        }
        .overlay {
            if compact && replacesFavicon {
                closeControl(focused: $slotCloseFocused)
                    .opacity(hovering || slotCloseFocused ? 1 : 0)
                    .allowsHitTesting(hovering || slotCloseFocused)
            }
        }
        .overlay { TabMiddleClick { closeTab() } }
        .aetherPointingCursor()
        .zIndex(topFused ? (selected ? 5 : 1) : 0)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .contextMenu {
            Button("New Tab") { withAnimation(AetherMotion.tab(reduced)) { _ = window.newTab() } }
            Button("New Private Tab") { withAnimation(AetherMotion.tab(reduced)) { _ = window.newPrivateTab() } }
            Button("Duplicate Tab") { withAnimation(AetherMotion.tab(reduced)) { window.duplicate(tab.id) } }
            Button("Open Beside") { if let url = tab.url { withAnimation(AetherMotion.tab(reduced)) { _ = window.openBeside(url: url) } } }.disabled(tab.url == nil)
            Button("Rename Tab…") { window.renamingTabID = tab.id }
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { withAnimation(AetherMotion.tab(reduced)) { window.togglePin(tab.id) } }
            Button(tab.isMuted ? "Unmute Tab" : "Mute Tab") { window.toggleMute(tab) }
                .disabled(tab.enginePageID == nil)
            Button(tab.isSleeping ? "Wake Tab" : "Sleep Tab") { tab.isSleeping ? window.select(tab.id) : window.sleepTab(tab.id) }
                .disabled(tab.enginePageID == nil && !tab.isSleeping)
            Button("Share Page…") { window.sharePage(for: tab) }.disabled(tab.url == nil)
            Button("Copy as Markdown Link") { window.copyMarkdownLink(for: tab) }.disabled(tab.url == nil)
            Divider()
            Button("Close Other Tabs") { withAnimation(AetherMotion.closeTab(reduced)) { window.closeOthers(tab.id) } }
            Button("Close Tab") { withAnimation(AetherMotion.closeTab(reduced)) { window.closeOrPutDown(tab.id) } }
        }
        .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let source = object as? String, let id = UUID(uuidString: source) else { return }
                Task { @MainActor in withAnimation(AetherMotion.tab(reduced)) { window.moveTab(id, before: tab.id) } }
            }
            return true
        }
        .accessibilityLabel(Text("\(tab.title), \(selected ? "selected tab" : "tab")"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sidebarWidth: CGFloat {
        window.workspace.preferences.transientSidebarWidth ?? window.workspace.preferences.sidebarWidth
    }

    /// The inset the row's content sits at, and the inset the trailing close
    /// control has to reproduce to land where it used to sit in the row.
    private var horizontalPadding: CGFloat { compact ? 2 : (topFused ? 8 : 10) }
    /// What the close control used to occupy in the row's stack: 10pt of spacing
    /// plus the 24pt button.
    private var closeWidthReserve: CGFloat { 34 }

    private func closeControl(focused: FocusState<Bool>.Binding) -> some View {
        Button { closeTab() } label: {
            BrowserIconView(icon: .close, tint: closeTint).iconSize(10)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherPointingCursor()
        .focusEffectDisabled()
        .focused(focused)
        .help("Close tab")
    }

    /// Sending the tab away and animating the tab list are the same act, so the
    /// animation is raised here, where the tab going is known — not by an
    /// `animation(_:value:)` on the whole sidebar, which also animated every
    /// reorder the list ever did and left each close inside a relayout of the
    /// tabs it was not about.
    private func closeTab() {
        withAnimation(AetherMotion.closeTab(reduced)) { window.close(tab.id) }
    }

    private var replacesFavicon: Bool {
        compact && topFused && !tab.isPinned && tab.loadState != .loading
    }

    @ViewBuilder private var selectionBackground: some View {
        if topFused {
            if selected {
                fusedActive
            } else if hovering {
                FusedTopTabShape(leftFoot: !isFirst)
                    .fill(chrome?.hover ?? theme.hover)
            }
        } else if selected {
            // The one deliberate glass surface in the app: the selected sidebar
            // row. Everything else is solid chrome or a native blur card.
            let shape = RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
            shape.fill(.clear)
                .glassEffect(.regular.tint((chrome?.isDark ?? theme.dark)
                                            ? Color.black.opacity(0.20)
                                            : Color.white.opacity(0.35)), in: shape)
                .glassEffectTransition(.materialize)
        } else if hovering {
            let hoverShape = RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
            hoverShape.fill(chrome?.sidebarHover ?? (theme.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
        }
    }

    /// Filled with the toolbar tone so the active tab fuses into the address row
    /// below it — one chrome piece, no seam to bridge with a negative offset.
    @ViewBuilder private var fusedActive: some View {
        FusedTopTabShape(leftFoot: !isFirst)
            .fill(chrome?.toolbarBG ?? theme.chrome)
    }
}

private struct SidebarHoverPreview: View {
    @Environment(\.aetherTheme) private var theme
    let tab: BrowserTab
    let isNewTab: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tab.title)
                .font(AetherType.emphasis(12))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            Text(isNewTab ? "Ask anything…" : (URL(string: tab.url ?? "")?.host ?? tab.url ?? ""))
                .font(AetherType.body(11))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 11, trailing: 10))
        .frame(width: 185, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous)
                .fill(theme.card)
        }
        .shadow(color: AetherShadow.floating(theme.dark).color,
                radius: AetherShadow.floating(theme.dark).radius,
                y: AetherShadow.floating(theme.dark).y)
        .allowsHitTesting(false)
    }
}

struct FusedTopTabShape: Shape {
    var leftFoot = true

    func path(in rect: CGRect) -> Path {
        let radius = min(AetherMetrics.tabRadius, rect.width / 2, rect.height / 2)
        let shoulder = min(CGFloat(12), rect.height - radius)
        let curve = radius * 0.55228475
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: left + radius, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + radius),
                      control1: CGPoint(x: right - radius + curve, y: top),
                      control2: CGPoint(x: right, y: top + radius - curve))
        path.addLine(to: CGPoint(x: right, y: bottom - shoulder))
        path.addCurve(to: CGPoint(x: right + shoulder, y: bottom),
                      control1: CGPoint(x: right, y: bottom - shoulder * 0.45),
                      control2: CGPoint(x: right + shoulder * 0.45, y: bottom))
        path.addLine(to: CGPoint(x: leftFoot ? left - shoulder : left, y: bottom))
        if leftFoot {
            path.addCurve(to: CGPoint(x: left, y: bottom - shoulder),
                          control1: CGPoint(x: left - shoulder * 0.45, y: bottom),
                          control2: CGPoint(x: left, y: bottom - shoulder * 0.45))
        }
        path.addLine(to: CGPoint(x: left, y: top + radius))
        path.addCurve(to: CGPoint(x: left + radius, y: top),
                      control1: CGPoint(x: left, y: top + radius - curve),
                      control2: CGPoint(x: left + radius - curve, y: top))
        path.closeSubpath()
        return path
    }
}
