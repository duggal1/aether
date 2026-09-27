import AppKit
import SwiftUI

public struct ReaderView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var markdown: String?
    @BrowserState private var error: String?
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    /// Reader is always the dark blur card: hudWindow/darkAqua frost, white
    /// text, light neutral pills with black ink. It never inherits the page's
    /// light surface — reading happens here, not on the website.
    private var skin: AetherSurfaceStyle {
        AetherSurfaceResolver.style(.darkWebsite, darkHomepage: true)
    }

    private var lightInk: Color {
        Color(.sRGB, red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, opacity: 1)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Reader").font(AetherType.panelTitle(19)).tracking(AetherTracking.heading)
                    .foregroundStyle(skin.primaryText)
                Spacer(minLength: 8)
                if let markdown {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(markdown, forType: .string)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "doc.on.doc")
                                .font(AetherType.symbol(13, weight: .medium))
                            Text("Copy")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(AetherLightActionButtonStyle())
                    .focusEffectDisabled()
                    .aetherPointingCursor()
                    Button {
                        let panel = NSSavePanel(); panel.nameFieldStringValue = "article.md"
                        if panel.runModal() == .OK, let url = panel.url {
                            try? markdown.write(to: url, atomically: true, encoding: .utf8)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            AetherCustomIconView(.downloadTray, tint: lightInk, size: 15)
                            Text("Export .md")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(AetherLightActionButtonStyle())
                    .focusEffectDisabled()
                    .aetherPointingCursor()
                }
                ChromeButton(.close, help: "Close") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            if let markdown {
                ScrollView {
                    Text(markdown)
                        .font(AetherType.body(14)).foregroundStyle(skin.primaryText)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: 700, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 26).padding(.bottom, 26)
                }
                .background { AetherOverlayScrollerTuning() }
            } else {
                AetherEmptyState(icon: .web, heading: "Reader is not connected",
                                 description: error ?? "The engine must provide Markdown derived from its live DOM. The original page must remain untouched.")
            }
        }
        .frame(width: 800, height: 560)
        .background { AetherSheetBackground() }
        .environment(\.aetherSurfaceStyle, skin)
        .environment(\.aetherChromeAppearance, .dark)
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
        .aetherSurfaceAppear()
        .task {
            guard let page = window.selected?.enginePageID,
                  let provider = window.workspace.engine as? any BrowserReaderProviding else { return }
            do { markdown = try await provider.markdown(pageID: page) }
            catch let failure { error = failure.localizedDescription }
        }
    }
}
