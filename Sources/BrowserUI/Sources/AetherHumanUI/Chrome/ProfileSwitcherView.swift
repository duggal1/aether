import SwiftUI

public struct ProfileSwitcherView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var showing = false
    @BrowserState private var creating = false
    @BrowserState private var profileName = ""
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    public var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: "circle.inset.filled").font(.system(size: 12)).foregroundStyle(theme.muted)
                Text(window.workspace.name(for: window.activeProfileID))
                    .font(AetherType.medium(12)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(theme.muted)
            }
            .foregroundStyle(theme.ink).padding(.horizontal, 11).frame(height: 31)
            .background { AetherGlassBackdrop(radius: 8, interactive: true) }
        }
        .buttonStyle(.plain)
        .help("Switch profile")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROFILES").font(AetherType.medium(10)).foregroundStyle(theme.soft)
                    .padding(.horizontal, 10).padding(.bottom, 5)
                ForEach(window.workspace.profiles) { profile in
                    Button {
                        window.switchProfile(profile.id)
                        showing = false
                    } label: {
                        HStack(spacing: 10) {
                            if profile.id == window.activeProfileID {
                                Image(systemName: "checkmark").frame(width: 11)
                            } else {
                                Color.clear.frame(width: 11, height: 11)
                            }
                            Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(theme.soft)
                            Text(profile.name).font(AetherType.body(12)).lineLimit(1)
                            Spacer()
                            if profile.id == window.activeProfileID { Text("Current").font(AetherType.body(10)).foregroundStyle(theme.muted) }
                        }
                        .foregroundStyle(theme.ink).padding(.horizontal, 10).frame(height: 29)
                        .background(profile.id == window.activeProfileID ? theme.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
                Rectangle().fill(theme.faintLine).frame(height: 1).padding(.vertical, 6)
                Button { creating = true } label: { menuLine("plus", "New Profile") }
                    .buttonStyle(.plain)
                SettingsLink { menuLine("gearshape", "Profile Settings") }
                    .buttonStyle(.plain)
            }
            .padding(9).frame(width: 230).background { AetherPopoverBackground() }
        }
        .sheet(isPresented: $creating) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Profile").font(AetherType.title(20))
                AetherField("Profile name", text: $profileName)
                HStack {
                    Spacer()
                    Button("Cancel") { creating = false }
                    Button("Create Profile") {
                        let profile = window.workspace.createProfile(profileName)
                        window.switchProfile(profile.id)
                        profileName = ""; creating = false; showing = false
                    }.keyboardShortcut(.defaultAction)
                        .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24).frame(width: 360).background(theme.canvas)
        }
    }
    private func menuLine(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 12)
            Text(title).font(AetherType.body(12))
            Spacer()
        }
        .foregroundStyle(theme.ink).padding(.horizontal, 10).frame(height: 29)
        .contentShape(Rectangle())
    }
}
