import AppKit
import SwiftUI

public struct ReaderView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var markdown: String?
    @BrowserState private var error: String?
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Reader").font(AetherType.panelTitle(19)).foregroundStyle(theme.heading)
                Spacer(minLength: 8)
                if let markdown {
                    Button("Copy Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(markdown, forType: .string)
                    }
                    .aetherButtonStyle()
                    Button("Export .md") {
                        let panel = NSSavePanel(); panel.nameFieldStringValue = "article.md"
                        if panel.runModal() == .OK, let url = panel.url {
                            try? markdown.write(to: url, atomically: true, encoding: .utf8)
                        }
                    }
                    .aetherButtonStyle()
                }
                ChromeButton(.close, help: "Close") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            if let markdown {
                ScrollView {
                    Text(markdown)
                        .font(AetherType.body(13)).foregroundStyle(theme.ink)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: 700, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 26).padding(.bottom, 26)
                }
            } else {
                AetherEmptyState(icon: .web, heading: "Reader is not connected",
                                 description: error ?? "The engine must provide Markdown derived from its live DOM. The original page must remain untouched.")
            }
        }
        .frame(width: 800, height: 560)
        .background(theme.raised)
        .task {
            guard let page = window.selected?.enginePageID,
                  let provider = window.workspace.engine as? any BrowserReaderProviding else { return }
            do { markdown = try await provider.markdown(pageID: page) }
            catch let failure { error = failure.localizedDescription }
        }
    }
}
