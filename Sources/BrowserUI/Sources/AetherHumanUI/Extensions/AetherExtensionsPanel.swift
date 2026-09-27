import AppKit
import SwiftUI

/// The extensions control that sits beside the space switcher.
///
/// Every installed extension is in here — pinned, unpinned and disabled alike.
/// The toolbar is for the ones you are using; this is the drawer, so unpinning
/// or disabling an extension removes it from the toolbar without removing it
/// from the list, and nothing disappears without being asked to.
@MainActor
public struct AetherExtensionsButton: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @ObservedObject private var extensions: AetherExtensions
    @BrowserState private var hovering = false
    let window: BrowserWindowModel

    public init(window: BrowserWindowModel) {
        self.window = window
        _extensions = ObservedObject(wrappedValue: .shared)
    }

    private var appearance: AetherChromeAppearance { chrome ?? (theme.dark ? .dark : .light) }
    private var count: Int { extensions.installed.count }

    public var body: some View {
        Button {
            window.showsExtensionsMenu.toggle()
            if window.showsExtensionsMenu { window.showsProfileMenu = false; window.showsMoreMenu = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 12, weight: .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(AetherType.caption(9.5))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(appearance.icon)
            .padding(.horizontal, count > 0 ? 8 : 0)
            .frame(minWidth: 22, minHeight: 22)
            .background {
                RoundedRectangle(cornerRadius: AetherMetrics.utilityRadius, style: .continuous)
                    .fill(hovering || window.showsExtensionsMenu
                          ? appearance.hover : appearance.hairline.opacity(0.6))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
        .animation(AetherMotion.hover(reduced), value: hovering)
        .onHover { hovering = $0 }
        .help(count == 0 ? "Extensions" : "Extensions (\(count))")
        .accessibilityLabel(count == 0 ? "Extensions" : "Extensions, \(count) installed")
    }
}

/// The drawer itself: the whole list, with pin, disable and remove on each row.
public struct AetherExtensionsPanel: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @ObservedObject private var extensions: AetherExtensions
    @BrowserState private var openMenuID: String? = nil
    let window: BrowserWindowModel

    public init(window: BrowserWindowModel) {
        self.window = window
        _extensions = ObservedObject(wrappedValue: .shared)
    }

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            if extensions.installed.isEmpty {
                empty
            } else {
                ForEach(extensions.installed) { item in
                    row(item)
                }
            }
            Divider().overlay(skin.separator).padding(.vertical, 5)
            installRow
            Divider().overlay(skin.separator).padding(.vertical, 5)
            nativeAction("gearshape", "Manage Extensions…") {
                window.showsExtensionsMenu = false
                window.showsSettings = true
            }
            if let error = extensions.error {
                Text(error)
                    .font(AetherType.caption(10.5))
                    .foregroundStyle(AetherPalette.error(skin.isDark))
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(6)
        .frame(width: 268)
        .background { AetherPopoverBackground() }
        .environment(\.aetherChromeAppearance, skin.isDark ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Extensions")
                .font(AetherType.caption(10.5))
                .foregroundStyle(skin.metadataText)
            Spacer(minLength: 0)
            Text("\(extensions.installed.count)")
                .font(AetherType.caption(10.5))
                .monospacedDigit()
                .foregroundStyle(skin.metadataText)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private var empty: some View {
        Text("Nothing installed yet.")
            .font(AetherType.body(12))
            .foregroundStyle(skin.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    /// One extension: it stays here whether it is pinned, unpinned or switched
    /// off, so the list is the record of what is installed rather than a view of
    /// what happens to be on the toolbar.
    private func row(_ item: AetherInstalledExtension) -> some View {
        HStack(spacing: 4) {
            Button {
                guard item.enabled else { return }
                extensions.press(item.id, profileID: window.activeProfileID)
            } label: {
                AetherMenuRow(radius: 8) {
                    HStack(spacing: 9) {
                        icon(item)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(AetherType.body(12))
                                .foregroundStyle(skin.primaryText)
                                .lineLimit(1)
                            Text(item.enabled ? "Version \(item.version)" : "Off · version \(item.version)")
                                .font(AetherType.caption(10))
                                .foregroundStyle(skin.metadataText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(AetherMenuPressStyle())
            .focusEffectDisabled()
            .help(item.enabled ? "Use \(item.name)" : "\(item.name) is off")

            Button {
                openMenuID = (openMenuID == item.id) ? nil : item.id
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(skin.secondaryIcon)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AetherMenuPressStyle())
            .focusEffectDisabled()
            .help("Extension actions")
            .popover(isPresented: Binding(
                get: { openMenuID == item.id },
                set: { if !$0 { openMenuID = nil } }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    menuRow(item.enabled ? "Unpin from Toolbar" : "Pin to Toolbar") {
                        openMenuID = nil
                        extensions.setEnabled(item.id, enabled: !item.enabled)
                    }
                    menuRow("Manage This Extension…") {
                        openMenuID = nil
                        window.showsExtensionsMenu = false
                        window.showsSettings = true
                    }
                    Divider().overlay(skin.separator).padding(.vertical, 4)
                    menuRow("Remove “\(item.name)”", destructive: true) {
                        openMenuID = nil
                        extensions.remove(item.id)
                    }
                }
                .padding(5)
                .frame(width: 224)
                .background { AetherPopoverBackground() }
                .environment(\.aetherChromeAppearance, skin.isDark ? .dark : .light)
                .onExitCommand { openMenuID = nil }
            }
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder private func icon(_ item: AetherInstalledExtension) -> some View {
        let image = extensions.actionIcon(item.id, profileID: window.activeProfileID)
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 13))
                    .foregroundStyle(item.enabled ? skin.primaryIcon : skin.secondaryIcon)
            }
        }
        .frame(width: 18, height: 18)
        .opacity(item.enabled ? 1 : 0.45)
    }

    /// The only way in: the Chrome Web Store, where each extension's own
    /// page installs it. No IDs to copy — tap, and the store opens.
    private var installRow: some View {
        Button {
            window.showsExtensionsMenu = false
            _ = window.newTab(url: AetherExtensions.webStore.absoluteString)
        } label: {
            AetherMenuRow(radius: 8) {
                HStack(spacing: 10) {
                    AetherCustomIconView(.downloadTray, tint: skin.primaryIcon, size: 14)
                        .frame(width: 20, height: 20, alignment: .center)
                    Text("Install Chrome Extension").font(AetherType.body(12))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(skin.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(AetherMenuPressStyle())
        .focusEffectDisabled()
    }

    /// One row of the custom per-extension dropdown: the same card, type and
    /// geometry as the panel's own rows, never the native menu.
    private func menuRow(_ title: String, destructive: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AetherMenuRow(radius: 8) {
                Text(title)
                    .font(AetherType.body(12))
                    .foregroundStyle(destructive ? AetherPalette.error(skin.isDark) : skin.primaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(height: 30, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(AetherMenuPressStyle())
        .focusEffectDisabled()
    }

    /// Native-symbol rows (correction pass §§3–4, §15): download/install and
    /// settings affordances use SF Symbols, never hand-drawn icons. Same row
    /// geometry as `action(_:_:)` so the list stays visually uniform.
    private func nativeAction(_ symbol: String, _ title: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AetherMenuRow(radius: 8) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(skin.primaryIcon)
                        .frame(width: 20, height: 20, alignment: .center)
                    Text(title).font(AetherType.body(12))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(skin.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(AetherMenuPressStyle())
        .focusEffectDisabled()
    }
}
