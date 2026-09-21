import AppKit
import SwiftUI

public struct DomainIcon: View {
    @Environment(\.aetherTheme) private var theme
    @State private var image: NSImage?
    let url: String?
    let size: CGFloat

    public init(_ url: String?, size: CGFloat = 16) {
        self.url = url
        self.size = size
    }

    private var host: String? {
        guard let host = url.flatMap({ URL(string: $0)?.host }), !host.isEmpty else { return nil }
        return host
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * 0.9, height: size * 0.9)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else if host != nil {
                Image(systemName: AetherSymbol.globe.rawValue)
                    .font(AetherType.symbol(size * 0.68))
                    .foregroundStyle(theme.muted)
            } else {
                AetherLogo()
                    .frame(width: size * 0.78, height: size * 0.78)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: host ?? "") {
            image = AetherFaviconStore.shared.cachedImage(for: host ?? "")
            guard image == nil, let host else { return }
            image = await AetherFaviconStore.shared.image(for: host)
        }
    }
}
