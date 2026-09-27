import SwiftUI

/// Modal actions. The primary button is the inverse of the surface it sits on
/// and the secondary button is a raised neutral — both read correctly in light
/// and dark, instead of being hard-coded light-on-dark.
public struct AetherModalActionButtonStyle: ButtonStyle {
    public enum Role: Equatable {
        case secondary
        case confirm
    }

    @Environment(\.aetherTheme) private var theme
    public let role: Role

    public init(role: Role) {
        self.role = role
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AetherType.body(13))
            .foregroundStyle(role == .confirm ? theme.background : theme.ink)
            .padding(.horizontal, 14)
            .frame(minWidth: 96, minHeight: 34)
            .background {
                RoundedRectangle(cornerRadius: AetherMetrics.utilityRadius, style: .continuous)
                    .fill(role == .confirm ? theme.ink : theme.settingsRaised)
            }
            .contentShape(RoundedRectangle(cornerRadius: AetherMetrics.utilityRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

/// Panel actions that sit on a floating card — Import, Export, Clear History.
///
/// One pair of tokens for the whole family, resolved from the surface: on a
/// light card the pill is `#FAFAFA` with `#171717` ink, and on a dark card it is
/// a translucent white lift with white ink. Import and Export can never end up
/// looking like two unrelated controls, and neither can a light card inherit the
/// dark button or the other way round.
public struct AetherPanelActionButtonStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.isEnabled) private var enabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let skin = surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
        let shape = RoundedRectangle(cornerRadius: AetherMetrics.utilityRadius, style: .continuous)
        return configuration.label
            .font(AetherType.body(13))
            .foregroundStyle(skin.panelActionInk)
            .padding(.horizontal, 14)
            .frame(minWidth: 104, minHeight: 30)
            .background {
                shape.fill(skin.panelActionFill)
                    .overlay { shape.strokeBorder(skin.cardBorder, lineWidth: 0.5) }
            }
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.45)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

// There is one panel action style — `AetherPanelActionButtonStyle` above. The
// previous second one was theme-driven, so a panel could render a button from a
// different palette than the button next to it.

/// Light neutral action pill — Install, Reader Copy/Export. Always `#F5F5F5`
/// with near-black ink, even on dark blur cards: it is the prominent action,
/// so it inverts against the card instead of inheriting it. Compact height,
/// normal macOS proportions. The caller supplies the prefix (tray/download
/// glyph) + label.
public struct AetherLightActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: AetherMetrics.utilityRadius, style: .continuous)
        return configuration.label
            .font(AetherType.body(13))
            .foregroundStyle(Color(.sRGB, red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, opacity: 1))
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background {
                shape.fill(Color(.sRGB, red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255, opacity: 1))
                    .overlay { shape.strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5) }
            }
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.45)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

