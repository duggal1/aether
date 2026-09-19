import Foundation

public enum DesignReference {
    public static func render(manifest: CaptureManifest) -> String {
        """
        # Aether design reference

        Source: \(manifest.sourceURL)
        Final URL: \(manifest.finalURL)
        Engine: \(manifest.engineName)
        Viewport: \(manifest.viewport.width) × \(manifest.viewport.height) @ \(manifest.viewport.scale)x

        Read `manifest.json` first, then `sections.json` and `styles/index.json`.
        `website.html` is the rendered live-document serialization, not a second unauthenticated HTTP fetch.
        `styles/*.css` contain source/CSSOM text supplied by Aether's engine, not a claim of perfect offline replay.
        `computed-styles.json` contains layout-element snapshots where requested.
        `screenshots/` contains native scrolling viewport tiles in document order.
        `full-page.*` exists only when the bounded native composite fits the configured pixel budget.
        `assets/` contains cached resources; inspect the manifest for missing/cross-origin/oversize assets.

        The output reflects one captured runtime state. Video, canvas, dynamic animations, cross-origin frames,
        private DOM state, and browser-controlled resources may not be recoverable as editable HTML and CSS.
        Sensitive inputs may be redacted by the engine. Inspect warnings before claiming full fidelity.
        \(manifest.truncated ? "\n**Warning: page capture was truncated or incomplete.**" : "")
        """
    }
}
