import SwiftUI

@MainActor
struct ExtensionsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @ObservedObject private var manager: AetherExtensions
    @BrowserState private var removingID: String?
    let workspace: BrowserWorkspace
    init(workspace: BrowserWorkspace) {
        self.workspace = workspace
        _manager = ObservedObject(wrappedValue: .shared)
    }

    private var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { manager.installFolder() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "folder")
                                .font(AetherType.symbol(13, weight: .medium))
                            Text("Load Unpacked Extension…")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(skin.primaryText)
                    .font(AetherType.body(13))
                    .aetherPointingCursor()
                    .focusEffectDisabled()
                    .disabled(manager.busy)
                    if manager.busy { ProgressView().controlSize(.small) }
                    Spacer()
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                if let error = manager.error {
                    Text(error)
                        .font(AetherType.body(11))
                        .foregroundStyle(AetherPalette.error(skin.isDark))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 13)
                        .padding(.bottom, 10)
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Installed")
            SettingsCard {
                if manager.installed.isEmpty {
                    Text("No extensions installed.")
                        .font(AetherType.body(12)).foregroundStyle(skin.secondaryText)
                        .padding(.horizontal, 13).padding(.vertical, 11)
                } else {
                    ForEach(Array(manager.installed.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SettingsDivider() }
                        extensionRow(item)
                    }
                }
            }
        }
        .confirmationDialog("Remove this extension?", isPresented: Binding(
            get: { removingID != nil },
            set: { if !$0 { removingID = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Extension", role: .destructive) {
                if let removingID { manager.remove(removingID) }
                removingID = nil
            }
        }
    }

    /// The extension's own icon leads — same as the toolbar panel — with the
    /// native puzzlepiece only as fallback. Never a drawn icon.
    private func extensionRow(_ item: AetherInstalledExtension) -> some View {
        HStack(alignment: .center, spacing: 13) {
            Group {
                if let image = manager.actionIcon(item.id, profileID: workspace.defaultProfileID) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .font(AetherType.symbol(17))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(skin.isDark ? Color.white : skin.primaryIcon)
                }
            }
            .frame(width: 21, height: 20, alignment: .center)
            .opacity(item.enabled ? 1 : 0.45)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(AetherType.emphasis(14))
                    .foregroundStyle(skin.primaryText)
                    .lineLimit(1)
                Text("Version \(item.version) · \(item.permissions.count) permissions")
                    .font(AetherType.body(12))
                    .foregroundStyle(skin.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                Toggle("Enabled", isOn: Binding(
                    get: { item.enabled },
                    set: { manager.setEnabled(item.id, enabled: $0) }
                ))
                .labelsHidden()
                Button("Remove") { removingID = item.id }
                    .buttonStyle(.plain)
                    .font(AetherType.body(12))
                    .foregroundStyle(skin.secondaryText)
                    .aetherPointingCursor()
                    .focusEffectDisabled()
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }
}
