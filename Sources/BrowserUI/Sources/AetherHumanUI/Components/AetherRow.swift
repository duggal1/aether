import SwiftUI

public struct AetherRow<Accessory: View>: View {
    @Environment(\.aetherTheme) private var theme
    let title: String
    let subtitle: String?
    let symbol: String?
    let accessory: Accessory
    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil,
                @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.accessory = accessory()
    }
    public var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(AetherType.symbol(13)).foregroundStyle(theme.muted)
                    .frame(width: 19)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AetherType.rowTitle()).foregroundStyle(theme.ink)
                if let subtitle {
                    Text(subtitle).font(AetherType.caption(11)).foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            accessory
        }
        .padding(.horizontal, 12)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(AetherType.sectionHeader(10)).tracking(0.4)
                .foregroundStyle(theme.soft)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous))
            if let footer {
                Text(footer).font(AetherType.caption(11)).foregroundStyle(theme.muted).padding(.leading, 4)
            }
        }
    }
}
