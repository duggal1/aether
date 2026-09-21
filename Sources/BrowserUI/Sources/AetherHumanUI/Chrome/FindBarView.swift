import SwiftUI

public struct FindBarView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var matches: Int?
    @BrowserState private var message: String?
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        HStack(spacing: 6) {
            AetherField("Find in page", text: Binding(get: { window.findQuery }, set: { window.findQuery = $0 }),
                        icon: .search, onSubmit: { find(true) })
                .frame(width: 232)
            if let matches {
                Text("\(matches) matches")
                    .font(AetherType.caption(11)).foregroundStyle(theme.muted)
                    .padding(.horizontal, 4)
            }
            if let message {
                Text(message).font(AetherType.caption(11)).foregroundStyle(theme.error)
            }
            ChromeButton(.arrowUp, help: "Previous match") { find(false) }
            ChromeButton(.arrowDown, help: "Next match") { find(true) }
            ChromeButton(.close, help: "Close find") { window.showsFind = false }
        }
        .padding(6)
        .background { AetherPopoverBackground() }
        .aetherGlassShadow(dark: theme.dark)
    }

    private func find(_ forward: Bool) {
        guard let page = window.selected?.enginePageID,
              let provider = window.workspace.engine as? any BrowserFindProviding else {
            message = "Engine not connected"; return
        }
        Task {
            do { matches = try await provider.find(pageID: page, query: window.findQuery, forward: forward); message = nil }
            catch { message = error.localizedDescription }
        }
    }
}
