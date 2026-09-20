import SwiftUI

public struct ProfileSwitcherView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var showing = false
    @BrowserState private var creating = false
    @BrowserState private var profileName = ""
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 6) {
                AetherLogo()
                    .frame(width: 14, height: 14)
                Text(window.workspace.name(for: window.activeProfileID))
                    .font(AetherType.body(13)).lineLimit(1)
                BrowserIconView(icon: .arrowDown, tint: theme.soft).iconSize(8)
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 6)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .help("Switch profile")
        .accessibilityLabel("Profile: \(window.workspace.name(for: window.activeProfileID))")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Text("PROFILES")
                    .font(AetherType.sectionHeader(10)).tracking(0.4)
                    .foregroundStyle(theme.soft)
                    .padding(.horizontal, 9).padding(.top, 4).padding(.bottom, 6)
                ForEach(Array(window.workspace.profiles.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        window.switchProfile(profile.id)
                        showing = false
                    } label: {
                        AetherMenuRow {
                            HStack(spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(AetherType.symbol(8)).foregroundStyle(theme.muted)
                                Text(profile.name).font(AetherType.body(12)).lineLimit(1)
                                Spacer(minLength: 6)
                                if index < 5 {
                                    Text("\u{2303}\(index + 1)")
                                        .font(AetherType.caption(11)).foregroundStyle(theme.soft)
                                }
                                if profile.id == window.activeProfileID {
                                    BrowserIconView(icon: .checkmark, tint: theme.muted).iconSize(11)
                                }
                            }
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 9).frame(height: 28)
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(AetherPressStyle(reduced: reduced))
                }
                Divider().padding(.vertical, 6)
                Button { creating = true } label: { menuLine(.plus, "New Profile") }
                    .buttonStyle(AetherPressStyle(reduced: reduced))
                Button { showing = false; window.showsSettings = true } label: { menuLine(.gear, "Profile Settings") }
                    .buttonStyle(AetherPressStyle(reduced: reduced))
            }
            .padding(7)
            .frame(width: 232)
            .background { AetherPopoverBackground() }
        }
        .sheet(isPresented: $creating) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Profile").font(AetherType.panelTitle(20)).foregroundStyle(theme.heading)
                AetherField("Profile name", text: $profileName)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { creating = false }
                        .buttonStyle(.plain)
                        .aetherFocusTreatment(radius: 6)
                    Button("Create Profile") {
                        let profile = window.workspace.createProfile(profileName)
                        window.switchProfile(profile.id)
                        profileName = ""; creating = false; showing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.hover)
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 360)
            .background(theme.raised)
        }
    }

    private func menuLine(_ icon: BrowserIcon, _ title: String) -> some View {
        AetherMenuRow {
            HStack(spacing: 10) {
                BrowserIconView(icon: icon, tint: theme.muted).iconSize(12)
                Text(title).font(AetherType.body(12))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 9).frame(height: 28)
            .contentShape(Rectangle())
        }
    }
}
