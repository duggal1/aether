import SwiftUI

public struct HistoryView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var query = ""
    @BrowserState private var confirmClear = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var results: [BrowserVisit] {
        window.workspace.visits.filter {
            $0.profileID == window.activeProfileID
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query))
        }
    }

    private var groups: [(title: String, visits: [BrowserVisit])] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [BrowserVisit]] = [:]
        for visit in results {
            let day = calendar.startOfDay(for: visit.visitedAt)
            let title: String
            if calendar.isDateInToday(day) { title = "Today" }
            else if calendar.isDateInYesterday(day) { title = "Yesterday" }
            else { title = day.formatted(date: .abbreviated, time: .omitted) }
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(visit)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("History").font(AetherType.panelTitle(20)).foregroundStyle(theme.heading)
                Spacer(minLength: 8)
                Button("Clear History") { confirmClear = true }
                    .aetherButtonStyle()
                    .tint(theme.error)
                    .disabled(results.isEmpty)
                ChromeButton(.close, help: "Close") { dismiss() }
            }
            AetherField("Search browsing history", text: $query, icon: .search)
            if results.isEmpty {
                AetherEmptyState(icon: .history, heading: "No history", description: "Pages you visit in this profile appear here.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title.uppercased())
                                    .font(AetherType.sectionHeader(10)).tracking(0.4)
                                    .foregroundStyle(theme.soft)
                                    .padding(.leading, 4)
                                ForEach(group.visits) { visit in
                                    visitRow(visit)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 680, height: 560)
        .background(theme.raised)
        .confirmationDialog("Clear history for this profile?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { window.workspace.clearHistory(window.activeProfileID) }
        } message: { Text("Browsing history for this profile will be removed from Aether's shell history.") }
    }

    private func visitRow(_ visit: BrowserVisit) -> some View {
        HoverSurface(radius: 8) {
            HStack(spacing: 12) {
                DomainIcon(visit.url, size: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(visit.title).font(AetherType.rowTitle(12.5)).lineLimit(1)
                    Text(visit.url).font(AetherType.caption(11)).foregroundStyle(theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(visit.visitedAt, style: .time)
                    .font(AetherType.caption(11)).foregroundStyle(theme.soft)
                ChromeButton(.close, help: "Delete visit", size: 24) {
                    window.workspace.deleteVisit(visit.id)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .onTapGesture { window.navigateSelected(visit.url); dismiss() }
    }
}
