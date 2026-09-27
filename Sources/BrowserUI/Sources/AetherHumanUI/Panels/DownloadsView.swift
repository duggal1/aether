import AppKit
import SwiftUI

// Downloads card: the shared native blur-card shell, no glass.
public struct DownloadsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var entries: [BrowserDownloadRecord] = []
    @BrowserState private var failure: String?
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if entries.isEmpty {
                AetherEmptyState(icon: .download, heading: "No downloads",
                                 description: failure ?? "Downloads will appear here.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { item in
                            DownloadRow(item: item, window: window, reload: { await reload() })
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 720, height: 555)
        .background { AetherSheetBackground() }
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
        .presentationBackground(.clear)
        .aetherSurfaceAppear()
        .task { await reload() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Downloads")
                .font(AetherType.panelTitle(20))
                .tracking(AetherTracking.heading)
                .foregroundStyle(skin.primaryText)
            Spacer(minLength: 8)
            Button("Refresh") { Task { await reload() } }
                .buttonStyle(AetherPanelActionButtonStyle())
                .focusEffectDisabled()
                .aetherPointingCursor()
            ChromeButton(.close, help: "Close", size: 24) { dismiss() }
                .padding(.leading, 4)
        }
    }

    private func reload() async {
        guard let provider = window.workspace.engine as? any BrowserDownloadsProviding else { return }
        do { entries = try await provider.downloads(profileID: window.activeProfileID) }
        catch { failure = error.localizedDescription }
    }
}

private struct DownloadRow: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    let item: BrowserDownloadRecord
    let window: BrowserWindowModel
    let reload: () async -> Void

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    var body: some View {
        HoverSurface(radius: 8) {
            HStack(spacing: 12) {
                AetherCustomIconView(AetherCustomIcon.fileIcon(for: item.fileName),
                                     tint: skin.secondaryIcon, size: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileName).font(AetherType.body(12.5))
                        .foregroundStyle(skin.primaryText).lineLimit(1)
                    if !item.isComplete, let total = item.totalBytes, total > 0 {
                        ProgressView(value: Double(item.bytesReceived), total: Double(total))
                    } else {
                        Text(item.isComplete ? "Complete" : "Downloading")
                            .font(AetherType.caption(11)).foregroundStyle(skin.metadataText)
                    }
                }
                Spacer(minLength: 8)
                if item.isComplete, let url = item.localFileURL {
                    ChromeButton(.downloadFolder, help: "Reveal in Finder", size: 24) {
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
