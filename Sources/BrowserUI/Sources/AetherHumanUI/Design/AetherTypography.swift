import SwiftUI

public enum AetherType {
    public static func body(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular) }
    public static func caption(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular) }
    public static func emphasis(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium) }
    public static func rowTitle(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium) }
    public static func panelTitle(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .medium) }
    public static func sectionHeader(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .medium) }
    public static func placeholder(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .regular) }
    public static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular, design: .monospaced) }

    public static func medium(_ size: CGFloat = 13) -> Font { emphasis(size) }
    public static func title(_ size: CGFloat = 20) -> Font { emphasis(size) }

    public static func symbol(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }}

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
