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

    private enum Mode: String, CaseIterable, Identifiable {
        case elements = "Elements"
        case styles = "Styles"
        case console = "Console"
        case network = "Network"
        var id: String { rawValue }
    }

    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Inspector").font(AetherType.panelTitle(19)).foregroundStyle(theme.heading)
                Spacer(minLength: 8)
                if let inspected {
                    Button("Copy HTML") { copy(inspected.documentHTML) }.aetherButtonStyle()
                    Button("Copy CSS") { copy(inspected.availableCSS) }.aetherButtonStyle()
                    Button("Export") { export(inspected.documentHTML, name: "aether-document.html") }.aetherButtonStyle()
                }
                ChromeButton(.close, help: "Close") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            if let inspected {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
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
                                        .frame(height: 25)
                                        .background(selected == node.id ? theme.hover : .clear,
                                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .contextMenu { Button("Copy Element HTML") { copy(node.html) } }
                            }
                        case .styles:
                            Text(inspected.availableCSS).font(AetherType.mono(11)).textSelection(.enabled)
                        case .console:
                            ForEach(inspected.consoleMessages, id: \.self) { Text($0).font(AetherType.mono(11)).textSelection(.enabled) }
                        case .network:
                            ForEach(inspected.networkRequests, id: \.self) { Text($0).font(AetherType.mono(11)).textSelection(.enabled) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                AetherEmptyState(icon: .terminalArrowRight, heading: "Inspector is not connected",
                                 description: failure ?? "Connect Aether's native DOM and diagnostic APIs to inspect the loaded page.")
            }
        }
        .frame(width: 820, height: 560)
        .background(theme.raised)
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
