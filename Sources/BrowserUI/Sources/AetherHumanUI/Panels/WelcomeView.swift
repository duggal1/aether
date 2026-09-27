import SwiftUI

// Ported from Search/Sources/Search/Welcome.swift (4-page first-run).
// What it is, import, holding (privacy), default-browser. Shown once.
public struct WelcomeView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var page = 0
    let window: BrowserWindowModel
    let onDone: () -> Void
    public init(window: BrowserWindowModel, onDone: @escaping () -> Void) {
        self.window = window; self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(["Aether is a native browser", "Bring your bookmarks", "Nothing leaves this Mac", "Make Aether default?"][page])
                .font(AetherType.panelTitle(17))
                .foregroundStyle(theme.heading)
            Text([
                "Tabs on top or in the sidebar. One address field. No account, no telemetry.",
                "Import bookmarks JSON from Settings, or keep the starter shortcuts.",
                "Passwords stay in Keychain. Private tabs never touch disk. Sleeping tabs save memory.",
                "Set Aether as default in macOS Settings to open links here."
            ][page])
                .font(AetherType.body(13)).foregroundStyle(theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            if page == 1 {
                HStack(spacing: 8) {
                    Button("Open Bookmarks") { window.showBookmarksPanel(); next() }.aetherButton()
                    Button("Keep Starters") { next() }.aetherButton()
                }
            } else if page == 3 {
                HStack(spacing: 8) {
                    Button("Done") { finish() }.aetherProminentButton()
                    Button("Open macOS Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference") {
                            NSWorkspace.shared.open(url)
                        }
                        finish()
                    }.aetherButton()
                }
            } else {
                Button(page == 2 ? "Got It" : "Continue") { next() }.aetherProminentButton()
            }
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(i == page ? theme.ink : theme.muted.opacity(0.3)).frame(width: 6, height: 6)
                }
            }
            Button("Skip") { finish() }.font(AetherType.body(11)).foregroundStyle(theme.muted).buttonStyle(.plain)
        }
        .padding(28)
        .frame(width: 480)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 30, y: 12)
    }

    private func next() { if page < 3 { page += 1 } else { finish() } }
    private func finish() {
        UserDefaults.standard.set(true, forKey: "aether.welcomed.v1")
        window.showsWelcome = false
        onDone()
    }
}
