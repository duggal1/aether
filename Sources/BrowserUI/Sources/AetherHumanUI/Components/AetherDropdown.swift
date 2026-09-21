import SwiftUI

public struct AetherDropdownOption<Value: Hashable & Sendable>: Identifiable, Sendable {
    public let value: Value
    public let title: String
    public let iconURL: String?
    public var id: Value { value }
    public init(value: Value, title: String, iconURL: String? = nil) {
        self.value = value
        self.title = title
        self.iconURL = iconURL
    }
}

public struct AetherDropdown<Value: Hashable & Sendable>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var open = false
    @State private var highlighted: Value?
    @Binding private var selection: Value
    private let options: [AetherDropdownOption<Value>]
    private let help: String?
    private let label: String

    public init(selection: Binding<Value>, options: [AetherDropdownOption<Value>],
                help: String? = nil, label: String) {
        _selection = selection
        self.options = options
        self.help = help
        self.label = label
    }

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? ""
    }

    private var selectedIconURL: String? {
        options.first(where: { $0.value == selection })?.iconURL
    }

    public var body: some View {
        Button {
            highlighted = selection
            withAnimation(AetherMotion.dropdown(reduced)) { open.toggle() }
        } label: {
            HStack(spacing: 9) {
                if let iconURL = selectedIconURL { DomainIcon(iconURL, size: 17) }
                Text(selectedTitle)
                    .font(AetherType.body(12))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                AetherSymbolView(open ? .discloseUp : .discloseDown, tint: theme.muted, size: 10)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 160, minHeight: 34)
            .background(theme.settingsRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
        .help(help ?? label)
        .accessibilityLabel(label)
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(options) { option in optionRow(option) }
            }
            .padding(5)
            .background { AetherPopoverBackground() }
            .frame(minWidth: 184)
            .onExitCommand { open = false }
        }
        .onChange(of: selection) { _, _ in open = false }
    }

    private func optionRow(_ option: AetherDropdownOption<Value>) -> some View {
        Button {
            selection = option.value
            withAnimation(AetherMotion.dropdown(reduced)) { open = false }
        } label: {
            HStack(spacing: 9) {
                if let iconURL = option.iconURL { DomainIcon(iconURL, size: 17) }
                Text(option.title)
                    .font(AetherType.body(12))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if option.value == selection {
                    AetherSymbolView(.confirm, tint: theme.muted, size: 11)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 9)
            .frame(height: 30, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowFill(option), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherPointingCursor()
        .focusEffectDisabled()
        .onHover { hovering in
            if hovering {
                withAnimation(AetherMotion.hover(reduced)) { highlighted = option.value }
            }
        }
        .accessibilityAddTraits(option.value == selection ? .isSelected : [])
    }

    private func rowFill(_ option: AetherDropdownOption<Value>) -> Color {
        if option.value == selection { return theme.selection }
        if option.value == highlighted { return theme.hover }
        return .clear
    }
}
