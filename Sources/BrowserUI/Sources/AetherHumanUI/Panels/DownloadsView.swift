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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Downloads").font(AetherType.panelTitle(20)).foregroundStyle(theme.heading)
                Spacer(minLength: 8)
                Button("Refresh") { Task { await reload() } }.aetherGlassButton()
                ChromeButton(.close, help: "Close") { dismiss() }
            }
            if entries.isEmpty {
                AetherEmptyState(icon: .download, heading: "No downloads",
                                 description: failure ?? "Downloads will appear here.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { item in
                            HoverSurface(radius: 8) {
                                HStack(spacing: 12) {
                                    AetherCustomIconView(AetherCustomIcon.fileIcon(for: item.fileName),
                                                         tint: theme.muted, size: 16)
                                     VStack(alignment: .leading, spacing: 4) {
                                         Text(item.fileName).font(AetherType.body(12.5)).lineLimit(1)
                                        if !item.isComplete, let total = item.totalBytes, total > 0 {
                                            ProgressView(value: Double(item.bytesReceived), total: Double(total))
                                        } else {
                                            Text(item.isComplete ? "Complete" : "Downloading")
                                                .font(AetherType.caption(11)).foregroundStyle(theme.muted)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if item.isComplete, let url = item.localFileURL {
                                        ChromeButton(.folder, help: "Reveal in Finder", size: 24) {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        }
                                    } else if !item.isComplete, let provider = window.workspace.engine as? any BrowserDownloadsProviding {
                                        ChromeButton(.close, help: "Cancel download", size: 24) {
                                            Task { try? await provider.cancelDownload(id: item.id, profileID: window.activeProfileID); await reload() }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 44)
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 620, height: 500)
        .background { AetherSheetBackground() }
        .task { await reload() }
    }

    private func reload() async {
        guard let provider = window.workspace.engine as? any BrowserDownloadsProviding else { return }
        do { entries = try await provider.downloads(profileID: window.activeProfileID) }
        catch { failure = error.localizedDescription }
    }
}
