import SwiftUI

// Ported from Search/Sources/Search/Peek.swift (Shift-click overlay tab).
// Lightweight preview card: Esc/outside/cross dismisses, Keep opens as tab
// beside current without double-load (uses stored URL exactly once).
public struct PeekOverlayView: View {
    @Environment(\.aetherTheme) private var theme
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        if let url = window.peekURL {
            ZStack {
                Color.black.opacity(0.22)
                    .contentShape(Rectangle())
                    .onTapGesture { window.peekURL = nil }
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        DomainIcon(url, size: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.peekTitle.isEmpty ? "Link preview" : window.peekTitle)
                                .font(AetherType.emphasis(13)).foregroundStyle(theme.ink).lineLimit(1)
                            Text(url).font(AetherType.body(11)).foregroundStyle(theme.muted).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Button { window.peekURL = nil } label: {
                            BrowserIconView(icon: .close, tint: theme.muted).iconSize(11)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain).help("Close (esc)")
                        Button { keep(url) } label: {
                            HStack(spacing: 4) {
                                BrowserIconView(icon: .plus, tint: theme.ink).iconSize(11)
                                Text("Keep as tab").font(AetherType.body(12))
                            }
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(theme.hover, in: Capsule())
                        }
                        .buttonStyle(.plain).help("Open as a tab beside this one")
                    }
                    .padding(12)
                    Divider()
                    VStack(spacing: 8) {
                        BrowserIconView(icon: .globe, tint: theme.muted).iconSize(26)
                        Text("Preview is off for this link type in this build.")
                            .font(AetherType.body(12)).foregroundStyle(theme.muted)
                        Button("Open Beside Instead") { keep(url) }
                            .aetherButton()
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .padding(16)
                }
                .frame(width: min(560, 640), alignment: .top)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 30, y: 10)
                .padding(40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func keep(_ url: String) {
        window.peekURL = nil
        _ = window.openBeside(url: url, select: true)
    }
}
