import AppKit
import SwiftUI

public struct AetherAppIcon: View {
    let side: CGFloat
    public init(side: CGFloat) { self.side = side }
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 185 / 1024, style: .continuous)
                .fill(AetherAppIconPalette.tile)
                .frame(width: side * 824 / 1024, height: side * 824 / 1024)
            AetherLogo()
                .frame(width: side * 824 / 1024 * 0.66, height: side * 824 / 1024 * 0.66)
                .environment(\.colorScheme, .dark)
        }
        .frame(width: side, height: side)
        .accessibilityLabel("Aether")
    }
}

public enum AetherAppIconPalette {
    public static let tile = Color(red: 28 / 255, green: 25 / 255, blue: 23 / 255)
}

public enum AetherAppIconError: Error {
    case renderFailed
}

public enum AetherAppIconImage {
    @MainActor public static func image(side: CGFloat) -> NSImage? {
        guard let cgImage = raster(side: side) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
    }

    @MainActor public static func writePNG(side: CGFloat, to url: URL) throws {
        guard let cgImage = raster(side: side), let data = pngData(from: cgImage) else {
            throw AetherAppIconError.renderFailed
        }
        try data.write(to: url)
    }

    @MainActor private static func raster(side: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: AetherAppIcon(side: side))
        renderer.scale = 1
        return renderer.cgImage
    }

    private static func pngData(from cgImage: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
