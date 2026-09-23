import SwiftUI

// One optical baseline for icons and titles, regardless of optional help copy.
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
                if let symbol {
                    Image(systemName: symbol)
                        .font(AetherType.symbol(17))
                        .foregroundStyle(theme.textStrong)
                        .frame(width: 21, height: 20, alignment: .center)
                } else if let customIcon {
                    AetherCustomIconView(customIcon, tint: theme.textStrong, size: 17)
                        .frame(width: 21, height: 20, alignment: .center)
                }
                Text(title).font(AetherType.emphasis(14)).foregroundStyle(theme.textStrong)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 10)
                accessory
            }
            if let subtitle {
                Text(subtitle).font(AetherType.body(12)).foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, (symbol == nil && customIcon == nil) ? 0 : 34)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }
}

public struct AetherSection<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    let title: String
    let footer: String?
    let content: Content

    public init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.footer = footer; self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(AetherType.emphasis(12)).foregroundStyle(theme.muted)
                .padding(.leading, 2)
            VStack(spacing: 0) { content }
                .background { AetherSettingsCardBackground() }
            if let footer {
                Text(footer).font(AetherType.caption(12)).foregroundStyle(theme.muted)
                    .padding(.leading, 2)
            }
        }
    }
}
