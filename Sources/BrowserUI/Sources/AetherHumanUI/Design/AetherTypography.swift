import SwiftUI

public enum AetherType {
    public static func body(_ size: CGFloat = 13) -> Font { AetherFontRegistry.font(size, .body) }
    public static func caption(_ size: CGFloat = 12) -> Font { AetherFontRegistry.font(size, .body) }
    public static func emphasis(_ size: CGFloat = 13) -> Font { AetherFontRegistry.font(size, .body) }
    public static func rowTitle(_ size: CGFloat = 13) -> Font { AetherFontRegistry.font(size, .body) }
    public static func panelTitle(_ size: CGFloat = 20) -> Font { AetherFontRegistry.font(size, .emphasis) }
    public static func sectionHeader(_ size: CGFloat = 10) -> Font { AetherFontRegistry.font(size, .emphasis) }
    public static func placeholder(_ size: CGFloat = 15) -> Font { AetherFontRegistry.font(size, .body) }
    public static func data(_ size: CGFloat = 12) -> Font { AetherFontRegistry.font(size, .medium) }

    public static func title(_ size: CGFloat = 20) -> Font { panelTitle(size) }

    public static func symbol(_ size: CGFloat, weight: Font.Weight = AetherIconStyle.weight) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

public enum AetherTracking {
    public static let heading: CGFloat = -0.3
}

public struct AetherTypographyScope<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) {
        AetherFontRegistry.install()
        self.content = content()
    }
    public var body: some View { content.environment(\.font, AetherType.body()) }
}

public extension View {
    func aetherTypography() -> some View { AetherTypographyScope { self } }
}
