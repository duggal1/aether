import SwiftUI

public struct AetherEmptyState: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    let icon: BrowserIcon
    let heading: String
    let description: String
    public init(icon: BrowserIcon, heading: String, description: String) {
        self.icon = icon; self.heading = heading; self.description = description
    }

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    public var body: some View {
        VStack(spacing: 12) {
            BrowserIconView(icon: icon, tint: skin.secondaryIcon)
                .iconSize(22)
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous)
                        .fill(skin.controlFill)
                }
            Text(heading).font(AetherType.rowTitle(14)).foregroundStyle(skin.primaryText)
            Text(description).font(AetherType.body(12)).foregroundStyle(skin.metadataText)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
