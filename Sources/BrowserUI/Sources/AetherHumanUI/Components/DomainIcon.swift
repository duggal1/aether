import AppKit
import SwiftUI

public struct DomainIcon: View {
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
            } else {
                Image(systemName: host == nil ? "square.dashed" : "globe")
                    .font(.system(size: size * 0.77, weight: .regular))
                    .foregroundStyle(.secondary)
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
