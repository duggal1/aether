import SwiftUI

public struct AetherRow<Accessory: View>: View {
    @Environment(\.aetherTheme) private var theme
    let title: String
    let subtitle: String?
    let symbol: String?
    let customIcon: AetherCustomIcon?
    let accessory: Accessory

    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil,
                customIcon: AetherCustomIcon? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.customIcon = customIcon
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 13) {
                rowIcon
                Text(title)
                    .font(AetherType.emphasis(14))
                    .foregroundStyle(theme.textStrong)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 10)
                accessory
            }
            if let subtitle {
                Text(subtitle)
                    .font(AetherType.body(12))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, hasIcon ? 34 : 0)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    private var hasIcon: Bool { symbol != nil || customIcon != nil }

    @ViewBuilder private var rowIcon: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(AetherType.symbol(17))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textStrong)
                .frame(width: 21, height: 20, alignment: .center)
        } else if let customIcon {
            AetherCustomIconView(customIcon, tint: theme.textStrong, size: 17)
                .frame(width: 21, height: 20, alignment: .center)
        }
    }
}

public struct AetherSection<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let title: String
    let footer: String?
    let content: Content

    public init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.footer = footer; self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(AetherType.emphasis(12))
                .foregroundStyle(theme.muted)
                .padding(.leading, 2)
            GlassEffectContainer(spacing: 4) {
                VStack(spacing: 0) { content }
            }
            .background { AetherSettingsCardBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(AetherMotion.container(reduced), value: title)
            if let footer {
                Text(footer)
                    .font(AetherType.caption(12))
                    .foregroundStyle(theme.muted)
                    .padding(.leading, 2)
            }
        }
    }
}
