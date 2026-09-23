import SwiftUI

/// Small semantic accents. Never tint the browser's neutral surfaces or use glass.
public enum AetherBadgeVariant: String, CaseIterable, Sendable {
    case sky, violet, yellow, rose, green, orange

    private var shades: (UInt, UInt, UInt) {
        // (600 background, 700 foreground in light mode, legible dark-mode foreground)
        switch self {
        case .sky:    (0x0284C7, 0x0369A1, 0x7DD3FC)
        case .violet: (0x7C3AED, 0x6D28D9, 0xC4B5FD)
        case .yellow: (0xCA8A04, 0xA16207, 0xFDE68A)
        case .rose:   (0xE11D48, 0xBE123C, 0xFDA4AF)
        case .green:  (0x16A34A, 0x15803D, 0x86EFAC)
        case .orange: (0xEA580C, 0xC2410C, 0xFDBA74)
        }
    }

    func background(_ dark: Bool) -> Color {
        switch self {
        case .green:
            return Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255, opacity: 0.12)
        default:
            return Self.hex(shades.0).opacity(0.19)
        }
    }
    func foreground(_ dark: Bool) -> Color {
        switch self {
        case .green:
            return dark ? Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255, opacity: 1)
                        : Self.hex(shades.1)
        default:
            return Self.hex(dark ? shades.2 : shades.1).opacity(1)
        }
    }

    private static func hex(_ hex: UInt) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255, opacity: 1)
    }
}

public struct AetherBadge: View {
    @Environment(\.aetherTheme) private var theme
    private let title: String
    private let variant: AetherBadgeVariant

    public init(_ title: String, variant: AetherBadgeVariant = .orange) {
        self.title = title
        self.variant = variant
    }

    public var body: some View {
        Text(title)
            .font(AetherType.emphasis(12))
            .foregroundStyle(variant.foreground(theme.dark))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(variant.background(theme.dark),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(title)
    }
}
