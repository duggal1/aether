import SwiftUI

public struct IncognitoToggleView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var showing = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        Button { showing.toggle() } label: {
            BrowserIconView(icon: .incognito, tint: window.isIncognito ? AetherProgressColor.neutral.color : theme.muted)
                .iconSize(15)
                .frame(width: 26, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
        .help(window.isIncognito ? "Incognito is on" : "Turn on incognito")
        .accessibilityLabel(window.isIncognito ? "Incognito is on" : "Turn on incognito")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 9) {
                        BrowserIconView(icon: .incognito,
                                        tint: window.isIncognito ? AetherProgressColor.neutral.color : theme.muted)
                            .iconSize(16)
                        Text("Incognito")
                            .font(AetherType.rowTitle(13))
                            .foregroundStyle(theme.ink)
                        Spacer(minLength: 8)
                        Toggle("Incognito", isOn: Binding(
                            get: { window.isIncognito },
                            set: { window.setIncognito($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    Text(window.isIncognito
                         ? "On. History stays out of this profile and tracking stays blocked."
                         : "Browse without saving history to this profile.")
                        .font(AetherType.caption(11))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
            .background { AetherPopoverBackground() }
            .frame(width: 232)
            .onExitCommand { showing = false }
        }
    }
}
