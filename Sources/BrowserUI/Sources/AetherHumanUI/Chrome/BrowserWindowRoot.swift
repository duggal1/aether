import AppKit
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
                .background { AetherWindowTransparencyView().allowsHitTesting(false) }
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


// Behind-window NSVisualEffectView can only sample desktop colors when the
// hosting window is non-opaque. The content pane paints its own opaque surface.
private struct AetherWindowTransparencyView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AetherWindowTransparencyProbe() }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class AetherWindowTransparencyProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
    }
}
