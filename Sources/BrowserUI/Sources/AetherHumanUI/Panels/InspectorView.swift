import AppKit
import SwiftUI

public struct InspectorView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var inspected: BrowserInspectionSnapshot?
    @BrowserState private var selected: String?
    @BrowserState private var mode: Mode = .elements
    @BrowserState private var failure: String?
    let window: BrowserWindowModel

    private enum Mode: String, CaseIterable { case elements = "Elements", styles = "Styles", console = "Console", network = "Network" }
    public init(window: BrowserWindowModel) { self.window = window }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector").font(AetherType.title(19))
                Spacer()
                if let inspected {
                    Button("Copy HTML") { copy(inspected.documentHTML) }
                    Button("Copy CSS") { copy(inspected.availableCSS) }
                    Button("Export") { export(inspected.documentHTML, name: "aether-document.html") }
                }
                ChromeButton("xmark", help: "Close") { dismiss() }
            }.padding(18)
            Rectangle().fill(theme.faintLine).frame(height: 1)
            if let inspected {
                HStack(spacing: 0) {
                    ForEach(Mode.allCases, id: \.self) { item in
                        Button { mode = item } label: {
                            Text(item.rawValue).font(AetherType.medium(12)).foregroundStyle(mode == item ? theme.ink : theme.muted)
                                .padding(.horizontal, 13).frame(height: 33)
                                .background(mode == item ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        switch mode {
                        case .elements:
                            ForEach(inspected.nodes) { node in
                                Button {
                                    selected = node.id
                                    if let port = window.workspace.engine as? any BrowserInspectionProviding,
                                       let page = window.selected?.enginePageID {
                                        Task { try? await port.highlight(nodeID: node.id, pageID: page) }
                                    }
                                } label: {
                                    Text(node.summary).font(AetherType.mono(11)).lineLimit(1)
                                        .foregroundStyle(theme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, CGFloat(min(node.depth, 12)) * 14 + 10)
                                        .frame(height: 26)
                                        .background(selected == node.id ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .contextMenu { Button("Copy Element HTML") { copy(node.html) } }
                            }
                        case .styles: Text(inspected.availableCSS).font(AetherType.mono(11)).textSelection(.enabled)
                        case .console: ForEach(inspected.consoleMessages, id: \.self) { Text($0).font(AetherType.mono(11)).textSelection(.enabled) }
                        case .network: ForEach(inspected.networkRequests, id: \.self) { Text($0).font(AetherType.mono(11)).textSelection(.enabled) }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                AetherEmptyState(symbol: "curlybraces", heading: "Inspector is not connected",
                                 description: failure ?? "Connect Aether's native DOM and diagnostic APIs to inspect the loaded page.")
            }
        }
        .frame(width: 850, height: 570)
        .background(theme.canvas)
        .task {
            guard let page = window.selected?.enginePageID,
                  let port = window.workspace.engine as? any BrowserInspectionProviding else { return }
            do { inspected = try await port.inspect(pageID: page) }
            catch { failure = error.localizedDescription }
        }
    }
    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
    private func export(_ text: String, name: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
