import SwiftUI

public struct HistoryView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var query = ""
    @BrowserState private var confirmClear = false
    @State private var closeHovering = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var results: [BrowserVisit] {
        window.workspace.visits.filter {
            $0.profileID == window.activeProfileID
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                    || $0.url.localizedCaseInsensitiveContains(query))
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
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 10) {
                Text("History").font(AetherType.panelTitle(22)).tracking(AetherTracking.heading)
                    .foregroundStyle(theme.textStrong)
                Spacer(minLength: 8)
                Button("Clear History") { confirmClear = true }
                    .aetherButton()
                    .frame(minWidth: 112, minHeight: 30)
                    .disabled(results.isEmpty)
                Button { window.showsHistory = false } label: {
                    Image(systemName: "xmark")
                        .font(AetherType.symbol(11))
                        .foregroundStyle(theme.muted)
                        .frame(width: 28, height: 28)
                        .background { AetherInteractionSurface(active: closeHovering, radius: 6) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .aetherPointingCursor()
                .onHover { closeHovering = $0 }
                .help("Close history")
            }

            AetherField("Search browsing history", text: $query, icon: .search)

            if results.isEmpty {
                AetherEmptyState(icon: .history, heading: "No history",
                                 description: "Pages you visit in this profile appear here.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groups, id: \.title) { group in
                            LazyVStack(alignment: .leading, spacing: 7) {
                                Text(group.title)
                                    .font(AetherType.emphasis(12))
                                    .foregroundStyle(theme.muted)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 7)
                                    .padding(.bottom, 3)
                                ForEach(group.visits) { visit in
                                    HistoryEntry(visit: visit,
                                                 open: {
                                                     window.navigateSelected(visit.url)
                                                     window.showsHistory = false
                                                 },
                                                 delete: { window.workspace.deleteVisit(visit.id) })
                                }
                            }
                        }
                    }
                    .padding(.bottom, 22)
                }
                .background { AetherOverlayScrollerTuning() }
                .mask {
                    if results.count > 7 {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0),
                                    .init(color: .black, location: 0.82),
                                    .init(color: .black.opacity(0.6), location: 0.92),
                                    .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle().fill(.black)
                    }
                }
            }
        }
        .padding(26)
        .frame(width: 720, height: 555)
        .background { AetherOverlayPanelBackground() }
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
        .confirmationDialog("Clear history for this profile?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) {
                window.workspace.clearHistory(window.activeProfileID)
            }
        } message: {
            Text("Browsing history for this profile will be removed from Aether's shell history.")
        }
    }
}

private struct HistoryEntry: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    let visit: BrowserVisit
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    DomainIcon(visit.url, size: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(visit.title)
                            .font(AetherType.emphasis(13))
                            .foregroundStyle(theme.textStrong)
                            .lineLimit(1)
                        Text(visit.url)
                            .font(AetherType.caption(11))
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text(visit.visitedAt, style: .time)
                        .font(AetherType.caption(12))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aetherPointingCursor()
            .focusEffectDisabled()
            Button(action: delete) {
                Image(systemName: "xmark")
                    .font(AetherType.symbol(12))
                    .foregroundStyle(theme.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aetherPointingCursor()
            .focusEffectDisabled()
            .help("Delete visit")
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(hovering ? theme.hover : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(AetherMotion.hover(reduced), value: hovering)
        .onHover { hovering = $0 }
    }
}
