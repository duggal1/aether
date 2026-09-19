# Browser and capture verification

Scope: native browser runtime, CLI/daemon, standalone AetherCapture and integrated adapter. No browser UI exists. Preserve the pre-existing untracked workspace.

1. Build all products in debug/release on Apple Silicon macOS, run both package suites serially with bounded process resources.
2. Add XCTest coverage under Sources/NativeCapture/Tests/AetherCaptureTests for real ImageIO encoding, raster integrity, exports, resources, geometry, cancellation, cleanup and concurrent sessions.
3. Exercise real runtime through local HTTP fixtures and daemon: navigation, history, DOM/JS/CSS, scrolling, cache/assets/downloads, profile isolation, lifecycle, repeated and concurrent captures.
4. Capture public sites with bounded time/memory, inspect images and manifests and record unsupported web-platform behavior honestly.
5. Reproduce failures, fix demonstrated causes, run regression and full suites, record timing/RSS, review changes and report remaining limits.

Environment: macOS 27.0, arm64, Swift 6.4 Command Line Tools. Prior local freeze investigation calls for one build job and serial tests.
