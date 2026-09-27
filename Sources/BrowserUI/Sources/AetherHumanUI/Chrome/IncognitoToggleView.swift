import SwiftUI

public struct IncognitoToggleView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var showing = false
    @State private var hovering = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var skin: AetherSurfaceStyle { surface ?? AetherSurfaceResolver.themed(dark: theme.dark) }

    public var body: some View {
        Button { showing.toggle() } label: {
            BrowserIconView(icon: .incognito, tint: chrome?.icon ?? theme.muted)
                .iconSize(16)
                .frame(width: 26, height: 30)
                .background { AetherInteractionSurface(active: hovering || showing || window.isIncognito, radius: 8, selected: window.isIncognito) }
                .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(window.isIncognito ? "Incognito is on" : "Turn on incognito")
        .accessibilityLabel(window.isIncognito ? "Incognito is on" : "Turn on incognito")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 9) {
                        BrowserIconView(icon: .incognito, tint: skin.primaryIcon)
                            .iconSize(16)
                        Text("Incognito")
                            .font(AetherType.rowTitle(13))
                            .fontWeight(.regular)
                            .foregroundStyle(skin.primaryText)
                        Spacer(minLength: 8)
                        Toggle("Incognito", isOn: Binding(
                            get: { window.isIncognito },
                            set: { window.setIncognito($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(window.isIncognito
                              ? (skin.isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.78))
                              : nil)
                    }
                    Text(window.isIncognito
                         ? "On. History stays out of this profile and tracking stays blocked."
                         : "Browse without saving history to this profile.")
                        .font(AetherType.caption(11))
                        .fontWeight(.regular)
                        .foregroundStyle(skin.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
            .background { AetherPopoverBackground() }
            .frame(width: 232)
            .presentationBackground(.clear)
            .preferredColorScheme(skin.isDark ? .dark : .light)
            .environment(\.aetherSurfaceStyle, skin)
            .onExitCommand { showing = false }
        }
    }
}
