import SwiftUI

public struct AetherEmptyState: View {
    @Environment(\.aetherTheme) private var theme
    let icon: BrowserIcon
    let heading: String
    let description: String
    public init(icon: BrowserIcon, heading: String, description: String) {
        self.icon = icon; self.heading = heading; self.description = description
    }
    public var body: some View {
        VStack(spacing: 12) {
            BrowserIconView(icon: icon, tint: theme.muted)
                .iconSize(22)
                .frame(width: 52, height: 52)
                .background { AetherCardBackground(radius: 13) }
            Text(heading).font(AetherType.rowTitle(14)).foregroundStyle(theme.heading)
            Text(description).font(AetherType.body(12)).foregroundStyle(theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
