import AppKit
import SwiftUI

public struct DownloadsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var entries: [BrowserDownloadRecord] = []
    @BrowserState private var failure: String?
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    public var body: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Downloads").font(AetherType.title(22))
                Spacer()
                Button("Refresh") { Task { await reload() } }
                ChromeButton("xmark", help: "Close") { dismiss() }
            }
            if entries.isEmpty {
                AetherEmptyState(symbol: "arrow.down.circle", heading: "No downloads",
                                 description: failure ?? "Download records from Aether's runtime will appear here when connected.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(entries) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "doc").foregroundStyle(theme.muted).frame(width: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.fileName).font(AetherType.medium(12)).lineLimit(1)
                                    if !item.isComplete, let total = item.totalBytes, total > 0 {
                                        ProgressView(value: Double(item.bytesReceived), total: Double(total))
                                    } else {
                                        Text(item.isComplete ? "Complete" : "Downloading")
                                            .font(AetherType.body(11)).foregroundStyle(theme.muted)
                                    }
                                }
                                Spacer()
                                if item.isComplete, let url = item.localFileURL {
                                    ChromeButton("folder", help: "Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                } else if !item.isComplete, let provider = window.workspace.engine as? any BrowserDownloadsProviding {
                                    ChromeButton("xmark", help: "Cancel download") {
                                        Task { try? await provider.cancelDownload(id: item.id, profileID: window.activeProfileID); await reload() }
                                    }
                                }
                            }
                            .padding(12).background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(22).frame(width: 600, height: 480).background(theme.canvas)
        .task { await reload() }
    }
    private func reload() async {
        guard let provider = window.workspace.engine as? any BrowserDownloadsProviding else { return }
        do { entries = try await provider.downloads(profileID: window.activeProfileID) }
        catch { failure = error.localizedDescription }
    }
}
