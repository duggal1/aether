import SwiftUI
import WebKit

// Ported from Search/Sources/Search/SiteCard.swift.
// Click-active-tab card: secure/cert steps, copy/print/zoom.
public struct SiteCardView: View {
    @Environment(\.aetherTheme) private var theme
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        if let tab = window.selected, let raw = tab.url, let url = URL(string: raw) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BrowserIconView(icon: tab.isSecure ? .lock : .warning, tint: tab.isSecure ? theme.muted : theme.error).iconSize(14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.host ?? raw).font(AetherType.emphasis(13)).foregroundStyle(theme.ink).lineLimit(1)
                        Text(tab.isSecure ? "Secure connection (https)" : "Not secure — be careful on this site")
                            .font(AetherType.body(11)).foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                Divider()
                HStack(spacing: 8) {
                    Button("Copy") { copy(raw) }.aetherButton()
                    Button("Print") { printPage() }.aetherButton()
                    Spacer(minLength: 0)
                    Button("−") { window.setZoom(window.zoomForHost(url.host) - 0.1, host: url.host); applyZoom() }.aetherButton()
                    Text("\(Int(window.zoomForHost(url.host) * 100))%").font(AetherType.body(12)).foregroundStyle(theme.muted).frame(minWidth: 44)
                    Button("+") { window.setZoom(window.zoomForHost(url.host) + 0.1, host: url.host); applyZoom() }.aetherButton()
                    Button("Reset") { window.setZoom(1.0, host: url.host); applyZoom() }.aetherButton()
                }
                if tab.isPrivateTab {
                    Text("Private tab — never saved to history or disk.")
                        .font(AetherType.body(11)).foregroundStyle(theme.muted)
                }
            }
            .padding(12)
            .frame(width: 320)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(radius: 20, y: 6)
        }
    }

    private func copy(_ raw: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
        window.showsSiteCard = false
    }
    private func printPage() {
        window.showsSiteCard = false
        NotificationCenter.default.post(name: NSNotification.Name("AetherPrintPage"), object: nil)
    }
    private func applyZoom() {
        guard let tab = window.selected, let pageID = tab.enginePageID else { return }
        guard let webView = window.workspace.engine.surface(pageID: pageID) as? WKWebView else { return }
        let host = tab.url.flatMap { URL(string: $0)?.host }
        let zoom = window.zoomForHost(host)
        // Persisted per host; live pageZoom where the surface supports it.
        webView.setValue(zoom, forKey: "pageZoom")
    }
}
