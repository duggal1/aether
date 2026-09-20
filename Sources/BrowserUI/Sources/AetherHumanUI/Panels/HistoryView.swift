import SwiftUI

public struct HistoryView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var query = ""
    @BrowserState private var confirmClear = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    private var results: [BrowserVisit] {
        window.workspace.visits.filter {
            $0.profileID == window.activeProfileID && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query))
        }
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("History").font(AetherType.title(24))
                Spacer()
                Button("Clear History") { confirmClear = true }.disabled(results.isEmpty)
                ChromeButton("xmark", help: "Close") { dismiss() }
            }
            AetherField("Search browsing history", text: $query, icon: "magnifyingglass")
            if results.isEmpty {
                AetherEmptyState(symbol: "clock", heading: "No history", description: "Pages you visit in this profile appear here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { visit in
                            HStack(spacing: 12) {
                                DomainIcon(visit.url, size: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(visit.title).font(AetherType.medium(12)).lineLimit(1)
                                    Text(visit.url).font(AetherType.body(11)).foregroundStyle(theme.muted).lineLimit(1)
                                }
                                Spacer()
                                Text(visit.visitedAt, style: .time).font(AetherType.body(11)).foregroundStyle(theme.soft)
                                ChromeButton("xmark", help: "Delete visit") { window.workspace.deleteVisit(visit.id) }
                            }
                            .padding(10).background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { window.navigateSelected(visit.url); dismiss() }
                        }
                    }
                }
            }
        }
        .padding(24).frame(width: 680, height: 560).background(theme.canvas)
        .confirmationDialog("Clear history for this profile?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { window.workspace.clearHistory(window.activeProfileID) }
        } message: { Text("Browsing history for this profile will be removed from Aether's shell history.") }
    }
}
