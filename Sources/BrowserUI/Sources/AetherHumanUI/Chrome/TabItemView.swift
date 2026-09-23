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

    private var tabTitleText: some View {
        Text(tab.title)
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
                .overlay {
                    if replacesFavicon {
                        Button { window.close(tab.id) } label: {
                            BrowserIconView(icon: .close, tint: closeTint).iconSize(10)
                                .frame(width: 19, height: 19)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .aetherPointingCursor()
                        .focusEffectDisabled()
                        .focused($slotCloseFocused)
                        .help("Close tab")
                        .opacity(hovering || slotCloseFocused ? 1 : 0)
                        .disabled(!hovering && !slotCloseFocused)
                        .transition(.opacity)
                    }
                }
                if !compact {
                    tabTitleText
                }
                if tab.loadState == .loading && topFused && !compact {
                    TerminalLoader().frame(width: 16, height: 16)
                } else if tab.isPinned && !compact {
                    BrowserIconView(icon: .pin, tint: theme.soft).iconSize(10)
                        .frame(width: 16, alignment: .center)
                }
                if !compact && topFused {
                    Button { window.close(tab.id) } label: {
                        BrowserIconView(icon: .close, tint: closeTint).iconSize(10)
                            .frame(width: 19, height: 19)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .aetherPointingCursor()
                    .focusEffectDisabled()
                        .focused($trailCloseFocused)
                        .help("Close tab")
                        .opacity((hovering || trailCloseFocused) ? 1 : 0)
                        .disabled(!hovering && !trailCloseFocused)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, compact ? 2 : (topFused ? 8 : 10))
            .frame(height: topFused ? AetherMetrics.tabHeight : 32)
            .background {
                selectionBackground
                    .animation(AetherMotion.tab(reduced), value: selected)
            }
            .contentShape(Rectangle())
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
        .aetherPointingCursor()
        .zIndex(topFused ? (selected ? 5 : 1) : 0)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .contextMenu {
            Button("New Tab") { _ = window.newTab() }
            Button("Duplicate Tab") { window.duplicate(tab.id) }
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { window.togglePin(tab.id) }
            Divider()
            Button("Close Other Tabs") { window.closeOthers(tab.id) }
            Button("Close Tab") { window.close(tab.id) }
        }
        .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let source = object as? String, let id = UUID(uuidString: source) else { return }
                Task { @MainActor in window.moveTab(id, before: tab.id) }
            }
            return true
        }
        .accessibilityLabel(Text("\(tab.title), \(selected ? "selected tab" : "tab")"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sidebarWidth: CGFloat {
        window.workspace.preferences.transientSidebarWidth ?? window.workspace.preferences.sidebarWidth
    }

    private var replacesFavicon: Bool {
        !tab.isPinned && tab.loadState != .loading && (compact || !topFused)
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
            let shape = RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
            shape.fill(.clear)
                .glassEffect(hovering
                             ? .regular.interactive().tint(Color.black.opacity(0.30))
                             : .regular.tint(Color.black.opacity(0.30)),
                             in: shape)
                .glassEffectTransition(.materialize)
        } else if hovering {
            let hoverShape = RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
            hoverShape.fill(.clear)
                .glassEffect(.regular.tint(Color.black.opacity(0.16)), in: hoverShape)
                .glassEffectTransition(.materialize)
        }
    }

    @ViewBuilder private var fusedActive: some View {
        FusedTopTabShape(leftFoot: !isFirst)
            .fill(chrome?.addressBG ?? theme.omnibox)
            .padding(.bottom, -1)
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
        .shadow(color: Color.black.opacity(theme.dark ? 0.08 : 0.04), radius: 6, y: 2)
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
