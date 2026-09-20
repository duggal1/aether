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
            HStack {
                Text("Reader").font(AetherType.title(19))
                Spacer()
                if let markdown {
                    Button("Copy Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(markdown, forType: .string)
                    }
                    Button("Export .md") {
                        let panel = NSSavePanel(); panel.nameFieldStringValue = "article.md"
                        if panel.runModal() == .OK, let url = panel.url {
                            try? markdown.write(to: url, atomically: true, encoding: .utf8)
                        }
                    }
                }
                ChromeButton("xmark", help: "Close") { dismiss() }
            }.padding(18)
            Rectangle().fill(theme.faintLine).frame(height: 1)
            if let markdown {
                ScrollView {
                    Text(markdown).font(AetherType.body(13)).foregroundStyle(theme.ink)
                        .textSelection(.enabled).frame(maxWidth: 700, alignment: .leading)
                        .frame(maxWidth: .infinity).padding(25)
                }
            } else {
                AetherEmptyState(symbol: "text.book.closed", heading: "Reader is not connected",
                                 description: error ?? "The engine must provide Markdown derived from its live DOM. The original page must remain untouched.")
            }
        }
        .frame(width: 830, height: 590).background(theme.canvas)
        .task {
            guard let page = window.selected?.enginePageID,
                  let provider = window.workspace.engine as? any BrowserReaderProviding else { return }
            do { markdown = try await provider.markdown(pageID: page) }
            catch let failure { error = failure.localizedDescription }
        }
    }
}
