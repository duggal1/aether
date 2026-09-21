import SwiftUI

public struct ProfileSwitcherView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var showing = false
    @BrowserState private var hovering = false
    @BrowserState private var creating = false
    @BrowserState private var profileName = ""
    @BrowserState private var newProfileColor = 0
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        Button { showing.toggle() } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(window.workspace.name(for: window.activeProfileID))
                        .font(AetherType.emphasis(12)).lineLimit(1)
                    BrowserIconView(icon: .arrowDown, tint: theme.muted).iconSize(9)
                }
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle().fill(theme.soft).frame(width: 3, height: 3)
                    }
                }
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 27)
            .background(hovering ? theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
        .onHover { value in withAnimation(AetherMotion.hover(reduced)) { hovering = value } }
        .help("Switch profile")
        .accessibilityLabel("Profile: \(window.workspace.name(for: window.activeProfileID))")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(window.workspace.profiles.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        window.switchProfile(profile.id)
                        showing = false
                    } label: {
                        AetherMenuRow(radius: 8) {
                            HStack(spacing: 8) {
                                if profile.id == window.activeProfileID {
                                    BrowserIconView(icon: .checkmark, tint: theme.muted).iconSize(10)
                                } else {
                                    Color.clear.frame(width: 20, height: 20)
                                }
                                Image(systemName: "circle.fill")
                                    .font(AetherType.symbol(9))
                                    .foregroundStyle(Self.swatch(for: profile))
                                Text(profile.name).font(AetherType.body(12)).lineLimit(1)
                                Spacer(minLength: 6)
                                if index < 5 {
                                    Text("\u{2303}\(index + 1)")
                                        .font(AetherType.caption(11)).foregroundStyle(theme.soft)
                                }
                            }
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 8).frame(height: 32)
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(AetherPressStyle(reduced: reduced))
                    .focusEffectDisabled()
                }
                Rectangle().fill(theme.faintLine).frame(height: 1).padding(.vertical, 5)
                Button { creating = true } label: { menuLine(.plus, "New Profile…") }
                    .buttonStyle(AetherPressStyle(reduced: reduced))
                    .focusEffectDisabled()
                Button { showing = false; window.showsSettings = true } label: { menuLine(.gear, "Profile Settings") }
                    .buttonStyle(AetherPressStyle(reduced: reduced))
                    .focusEffectDisabled()
            }
            .padding(6)
            .frame(width: 218)
            .background { AetherPopoverBackground() }
        }
        .sheet(isPresented: $creating) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Profile").font(AetherType.panelTitle(20)).foregroundStyle(theme.heading)
                AetherField("Profile name", text: $profileName)
                HStack(spacing: 14) {
                    ForEach(0..<Self.swatches.count, id: \.self) { index in
                        Button { newProfileColor = index } label: {
                            Circle()
                                .fill(Self.swatches[index])
                                .frame(width: 29, height: 29)
                                .overlay {
                                    if newProfileColor == index {
                                        Circle()
                                            .strokeBorder(Self.swatches[index], lineWidth: 2)
                                            .padding(-5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .aetherPointingCursor()
                        .aetherFocusTreatment(radius: 17)
                        .focusEffectDisabled()
                        .help("Profile color \(index + 1)")
                        .accessibilityLabel("Profile color \(index + 1)")
                    }
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { creating = false }
                        .buttonStyle(.plain)
                        .aetherPointingCursor()
                        .aetherFocusTreatment(radius: 6)
                        .focusEffectDisabled()
                    Button("Create Profile") {
                        let profile = window.workspace.createProfile(profileName, colorIndex: newProfileColor)
                        window.switchProfile(profile.id)
                        profileName = ""; newProfileColor = 0; creating = false; showing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .aetherGlassProminentButton()
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 388)
            .background(theme.raised)
        }
    }

    private func menuLine(_ icon: BrowserIcon, _ title: String) -> some View {
        AetherMenuRow(radius: 10) {
            HStack(spacing: 10) {
                BrowserIconView(icon: icon, tint: theme.muted).iconSize(12)
                Text(title).font(AetherType.body(12))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 9).frame(height: 34)
            .contentShape(Rectangle())
        }
    }

    static let swatches: [Color] = [
        Color(red: 0xFB / 255, green: 0xFB / 255, blue: 0xFB / 255),
        Color(red: 0x00 / 255, green: 0x8B / 255, blue: 0x5C / 255),
        Color(red: 0x00 / 255, green: 0x7F / 255, blue: 0xBC / 255),
        Color(red: 0x63 / 255, green: 0x5D / 255, blue: 0xA5 / 255),
        Color(red: 0xC9 / 255, green: 0x85 / 255, blue: 0x00 / 255),
        Color(red: 0xBD / 255, green: 0x56 / 255, blue: 0x6B / 255),
        Color(red: 0xCC / 255, green: 0x4A / 255, blue: 0x56 / 255),
        Color(red: 0xCA / 255, green: 0x51 / 255, blue: 0x26 / 255),
    ]

    static func swatchIndex(for profile: BrowserProfile) -> Int {
        if profile.colorIndex >= 0 { return profile.colorIndex % swatches.count }
        var hasher = Hasher()
        hasher.combine(profile.id)
        return abs(hasher.finalize()) % swatches.count
    }

    static func swatch(for profile: BrowserProfile) -> Color {
        swatches[swatchIndex(for: profile)]
    }
}
