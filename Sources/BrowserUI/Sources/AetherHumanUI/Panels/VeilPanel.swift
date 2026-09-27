import SwiftUI

// Search-port: Hidden.swift review list with hover-restore concept simplified
// to per-site list + restore-all + undo. Hiding itself is applied via
// VeilStore.css in BrowserWindowModel.applySiteCustomizations.
public struct VeilPanel: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var selector = ""
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var host: String? {
        window.selected?.url.flatMap { VeilStore.shared.host(of: $0) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hidden on \(host ?? "this site")")
                    .font(AetherType.panelTitle(15)).foregroundStyle(theme.heading)
                Spacer(minLength: 0)
                Button { window.showsVeils = false } label: {
                    BrowserIconView(icon: .close, tint: theme.muted).iconSize(11)
                }.buttonStyle(.plain)
            }
            if let host {
                let veils = VeilStore.shared.veils(on: host)
                if veils.isEmpty {
                    Text("Nothing hidden here yet. Paste a CSS selector to hide it on every visit.")
                        .font(AetherType.body(12)).foregroundStyle(theme.muted)
                } else {
                    ForEach(veils) { veil in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(veil.label).font(AetherType.body(12)).foregroundStyle(theme.ink).lineLimit(1)
                                Text(veil.selector).font(AetherType.body(10)).foregroundStyle(theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Button("Restore") { VeilStore.shared.restore(veil, on: host) }.aetherButton()
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Undo Last") { _ = VeilStore.shared.undo(on: host) }.aetherButton()
                        Button("Restore All") { VeilStore.shared.restoreAll(on: host) }.aetherButton()
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    TextField("Selector, e.g. .cookie-banner", text: $selector)
                        .textFieldStyle(.roundedBorder).font(AetherType.body(12))
                        .onSubmit { add(host: host) }
                    Button("Hide") { add(host: host) }.aetherProminentButton().disabled(selector.isEmpty)
                }
                Text("Applied before first paint via injected stylesheet.")
                    .font(AetherType.body(10)).foregroundStyle(theme.muted)
            } else {
                Text("Open a website first.").font(AetherType.body(12)).foregroundStyle(theme.muted)
            }
        }
        .padding(16)
        .frame(width: 400)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 24, y: 8)
    }

    private func add(host: String) {
        let sel = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sel.isEmpty else { return }
        VeilStore.shared.hide(sel, label: sel, note: "", on: host)
        selector = ""
    }
}
