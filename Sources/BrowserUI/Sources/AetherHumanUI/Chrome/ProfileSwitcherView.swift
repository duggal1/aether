import SwiftUI

public struct ProfileSwitcherView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var hovering = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var labelColor: Color { chrome?.text ?? theme.ink }
    private var iconColor: Color { chrome?.icon ?? theme.muted }

    public var body: some View {
        Button {
            window.showsProfileMenu.toggle()
            window.showsMoreMenu = false
            window.showsExtensionsMenu = false
        } label: {
            HStack(spacing: 5) {
                Text(window.workspace.name(for: window.activeProfileID))
                    .font(AetherType.body(10.5)).lineLimit(1)
                    .fontWeight(.regular)
                BrowserIconView(icon: .arrowDown, tint: iconColor).iconSize(8)
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background { pickerGlass }
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
        .animation(AetherMotion.hover(reduced), value: hovering)
        .onHover { hovering = $0 }
        .help("Switch space")
        .accessibilityLabel("Space: \(window.workspace.name(for: window.activeProfileID))")
    }

    @ViewBuilder private var pickerGlass: some View {
        // Quiet solid pill, not a glass lens. The pill sits on chrome; a second
        // translucent layer on top of an already-solid surface only made the
        // control look like it was floating in a different window.
        let dark = appearance.isDark
        RoundedRectangle(cornerRadius: AetherMetrics.utilityRadius, style: .continuous)
            .fill(hovering || window.showsProfileMenu ? appearance.hover : appearance.hairline.opacity(0.6))
            .environment(\.colorScheme, dark ? .dark : .light)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var appearance: AetherChromeAppearance { chrome ?? (theme.dark ? .dark : .light) }
}

// Window-owned overlay panel: exact 8pt shape, no popover container chrome,
// so the rendered corners match the specified radius with no hollow ring.
public struct ProfileMenuPanel: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    private var labelColor: Color { skin.primaryText }
    private var iconColor: Color { skin.primaryIcon }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(window.workspace.profiles.enumerated()), id: \.element.id) { index, profile in
                Button {
                    window.switchProfile(profile.id)
                    window.showsProfileMenu = false
                } label: {
                    profileRow(profile, index: index)
                }
                .buttonStyle(AetherMenuPressStyle())
                .focusEffectDisabled()
            }
            Divider().overlay(skin.separator).padding(.vertical, 5)
            Button {
                window.showsRenameProfile = true
                window.showsProfileMenu = false
            } label: {
                AetherMenuRow(radius: 8) {
                    Text("Rename Space")
                        .font(AetherType.body(12))
                        .foregroundStyle(labelColor)
                        .padding(.horizontal, 9).frame(height: 32, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(AetherMenuPressStyle())
            .focusEffectDisabled()
            Divider().overlay(skin.separator).padding(.vertical, 5)
            actionRow(.plus, "New Space") {
                window.showsNewProfile = true
                window.showsProfileMenu = false
            }
            actionRow(.gear, "Space Settings") {
                window.showsProfileMenu = false
                window.showsSettings = true
            }
        }
        .padding(6)
        .frame(width: 218)
        .background { AetherPopoverBackground() }
        .environment(\.aetherChromeAppearance, skin.isDark ? .dark : .light)
    }

    private func profileRow(_ profile: BrowserProfile, index: Int) -> some View {
        AetherMenuRow(radius: 8) {
            HStack(spacing: 8) {
                if profile.id == window.activeProfileID {
                    BrowserIconView(icon: .checkmark, tint: iconColor).iconSize(10)
                } else {
                    Color.clear.frame(width: 20, height: 20)
                }
                Image(systemName: "circle.fill")
                    .font(AetherType.symbol(9))
                    .foregroundStyle(Self.swatch(for: profile))
                Text(profile.name)
                    .font(AetherType.body(12))
                    .fontWeight(.regular)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if index < 9 {
                    HStack(spacing: 3) {
                        AetherCustomIconView(.kbdCommand, tint: appearanceSecondary, size: 10)
                        Text("\(index + 1)")
                            .font(AetherType.caption(11))
                            .foregroundStyle(appearanceSecondary)
                    }
                }
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 8).frame(height: 32)
            .contentShape(Rectangle())
        }
    }

    private var appearanceSecondary: Color { skin.metadataText }

    private func actionRow(_ icon: BrowserIcon, _ title: String, enabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AetherMenuRow(radius: 8) {
                HStack(spacing: 10) {
                    BrowserIconView(icon: icon, tint: iconColor).iconSize(12)
                    Text(title).font(AetherType.body(12))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(enabled ? labelColor : appearanceSecondary)
                .padding(.horizontal, 9).frame(height: 32)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(AetherMenuPressStyle())
        .focusEffectDisabled()
        .disabled(!enabled)
    }

    static let swatches: [Color] = [
        Color(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255),
        Color(red: 0x00 / 255, green: 0xA5 / 255, blue: 0x6E / 255),
        Color(red: 0x00 / 255, green: 0x96 / 255, blue: 0xDE / 255),
        Color(red: 0x74 / 255, green: 0x6C / 255, blue: 0xC4 / 255),
        Color(red: 0xE8 / 255, green: 0x9B / 255, blue: 0x00 / 255),
        Color(red: 0xDC / 255, green: 0x64 / 255, blue: 0x7D / 255),
        Color(red: 0xF0 / 255, green: 0x55 / 255, blue: 0x63 / 255),
        Color(red: 0xEE / 255, green: 0x5F / 255, blue: 0x2C / 255),
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

public struct NewProfileSheet: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @BrowserState private var profileName = ""
    @BrowserState private var newProfileColor = 0
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    /// Space sheets are always real blur cards — dark frost in dark mode —
    /// never the opaque solid slab. The sheet usually opens over the New Tab
    /// page (`.homepage`, which renders solid), so map that to the matching
    /// website tokens; over a real website keep the shared resolved surface.
    private var skin: AetherSurfaceStyle {
        let outer = surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
        guard outer.isHomepage else { return outer }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Space").font(AetherType.panelTitle(20)).tracking(AetherTracking.heading).foregroundStyle(skin.primaryText)
            AetherField("Space name", text: $profileName, horizontalPadding: 12)
            HStack(spacing: 12) {
                ForEach(0..<ProfileMenuPanel.swatches.count, id: \.self) { index in
                    Button { newProfileColor = index } label: {
                        Circle()
                            .fill(ProfileMenuPanel.swatches[index])
                            .brightness(0.035)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if newProfileColor == index {
                                    Circle()
                                        .strokeBorder(skin.primaryText, lineWidth: 2)
                                        .padding(-4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .aetherPointingCursor()
                    .aetherFocusTreatment(radius: 16)
                    .focusEffectDisabled()
                    .help("Profile color \(index + 1)")
                    .accessibilityLabel("Profile color \(index + 1)")
                }
            }
            .padding(.top, 2)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { window.showsNewProfile = false }
                    .buttonStyle(AetherModalActionButtonStyle(role: .secondary))
                Button {
                    let profile = window.workspace.createProfile(profileName, colorIndex: newProfileColor)
                    window.switchProfile(profile.id)
                    window.showsNewProfile = false
                } label: {
                    HStack(spacing: 7) {
                        AetherCustomIconView(.arrowReturn, tint: saveInk, size: 13)
                        Text("Save")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(AetherModalActionButtonStyle(role: .confirm))
                .focusEffectDisabled()
                .aetherPointingCursor()
                .keyboardShortcut(.defaultAction)
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 388)
        .background { AetherSheetBackground() }
        .environment(\.aetherSurfaceStyle, skin)
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
        .presentationBackground(.clear)
        .aetherSurfaceAppear()
    }

    // Ink for the primary action's icon: the inverse of the button fill, which
    // is the anchor the shape itself is in (dark button on light, light on dark).
    private var saveInk: Color { theme.background }
}

public struct RenameProfileSheet: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @BrowserState private var renameText = ""
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    /// Same blur-card rule as New Space: never the opaque solid slab.
    private var skin: AetherSurfaceStyle {
        let outer = surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
        guard outer.isHomepage else { return outer }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Rename Profile").font(AetherType.panelTitle(20)).tracking(AetherTracking.heading).foregroundStyle(skin.primaryText)
            AetherField("Profile name", text: $renameText, horizontalPadding: 12)
                .onAppear {
                    if renameText.isEmpty {
                        renameText = window.workspace.name(for: window.activeProfileID)
                    }
                }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { window.showsRenameProfile = false }
                    .buttonStyle(AetherModalActionButtonStyle(role: .secondary))
                Button {
                    window.workspace.renameProfile(window.activeProfileID, to: renameText)
                    window.showsRenameProfile = false
                } label: {
                    HStack(spacing: 7) {
                        AetherCustomIconView(.arrowReturn, tint: saveInk, size: 13)
                        Text("Save")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(AetherModalActionButtonStyle(role: .confirm))
                .focusEffectDisabled()
                .aetherPointingCursor()
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 388)
        .background { AetherSheetBackground() }
        .environment(\.aetherSurfaceStyle, skin)
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
        .presentationBackground(.clear)
        .aetherSurfaceAppear()
    }

    // Ink for the primary action's icon: the inverse of the button fill, which
    // is the anchor the shape itself is in (dark button on light, light on dark).
    private var saveInk: Color { theme.background }
}
