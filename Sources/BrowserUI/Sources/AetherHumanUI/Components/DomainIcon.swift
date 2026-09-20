import SwiftUI

public struct DomainIcon: View {
    @Environment(\.aetherTheme) private var theme
    let url: String?
    let size: CGFloat
    public init(_ url: String?, size: CGFloat = 16) { self.url = url; self.size = size }
    public var body: some View {
        let host = url.flatMap { URL(string: $0)?.host } ?? ""
        ZStack {
            RoundedRectangle(cornerRadius: max(4, size * 0.24)).fill(theme.subtle)
            if host.isEmpty {
                Image(systemName: "square.dashed").font(.system(size: size * 0.55)).foregroundStyle(theme.muted)
            } else {
                Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                    .font(AetherType.medium(size * 0.58)).foregroundStyle(theme.muted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
