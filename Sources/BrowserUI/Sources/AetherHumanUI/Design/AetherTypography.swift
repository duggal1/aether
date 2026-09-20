import SwiftUI

public enum AetherType {
    public static func body(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular, design: .default) }
    public static func medium(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium, design: .default) }
    public static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
    public static func title(_ size: CGFloat = 24) -> Font { .system(size: size, weight: .regular, design: .default) }
}
