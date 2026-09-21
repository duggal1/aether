# Visible WebKit correctness and benchmark

Scope: fix authenticated CLI access; remove unreachable custom navigation/script/render paths; diagnose visible Clay rendering; use installed macOS 27 system WebKit without page-altering optimizations. Preserve unrelated UI edits.

Verification: serialized release build and focused Swift tests, authenticated app CLI, visible 20-site sequential run twice, concurrent visible-tab runs twice, content/CSS/image/navigation and screenshot evidence, explicit failures. Keep historical competitor title measurements; do not rank unlike measurements. Never launch a benchmark daemon.

Current evidence: host macOS 27.0 (26A5425a), Xcode Swift 6.4; runtime already unconditionally dispatches primary page APIs to WKWebView. CLI omits token handshake. Previous Aether 354ms median used browserd, not visible app.
