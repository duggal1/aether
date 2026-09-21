import SwiftUI

public struct BrowserWindowRoot: View {
    @BrowserState private var window: BrowserWindowModel?
    private let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) {
        self.workspace = workspace
    }
    public var body: some View {
        AetherThemeScope {
            if let window {
            BrowserWindowView(window: window)
                .aetherTypography()
                .ignoresSafeArea(.container, edges: .top)
                .focusedSceneValue(\.aetherWindow, window)
                .task { await window.restoreProfile() }
            }
        }
        .task {
            if window == nil { window = BrowserWindowModel(workspace: workspace) }
        }
    }
}
