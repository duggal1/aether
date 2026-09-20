import SwiftUI

public struct AetherEmptyState: View {
    @Environment(\.aetherTheme) private var theme
    let symbol: String
    let heading: String
    let description: String
    public init(symbol: String, heading: String, description: String) {
        self.symbol = symbol; self.heading = heading; self.description = description
    }
    public var body: some View {
        VStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 27, weight: .ultraLight)).foregroundStyle(theme.muted)
                .frame(width: 54, height: 54).background(theme.surface, in: RoundedRectangle(cornerRadius: 15))
            Text(heading).font(AetherType.medium(14)).foregroundStyle(theme.heading)
            Text(description).font(AetherType.body(12)).foregroundStyle(theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
