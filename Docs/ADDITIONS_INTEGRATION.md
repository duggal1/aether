# Aether additions integration review

This is an incremental integration into the existing Swift browser engine. `Sources/EngineAdditions/` was already committed to the repository; its nested package is a source drop, not the root application architecture.

## Integrated

- Root SwiftPM imports the existing `AetherNetworkHardening` source directory by explicit target path. The existing `Networking` and `Navigation` modules consume it; there is no second network service.
- `NavigationPipeline` checks response status and `X-Content-Type-Options: nosniff` before external JavaScript and stylesheet content is executed or parsed.
- Existing `HTTPCache` uses the addition's freshness parser instead of treating responses without explicit freshness as cacheable for sixty seconds. It skips private, validation-required, Set-Cookie, and Vary responses until correct keyed storage/revalidation is implemented.
- `NetworkSession` bypasses the shared URL cache on authenticated or cookie-bearing requests.
- Added targeted tests and a macOS runner workflow. Production platform validation requires Swift 6.2+ and a real macOS 15+ toolchain.

## Not integrated: reuse existing owners

- `AetherResourceControl` competes with the existing `FleetScheduler`, `ResourceLedger`, and page lifecycle. Do not install a second live planner.
- `AetherAgentInfrastructure` requires authenticated Unix-socket peer/capability identity before owner-based grants can be enforced. JSON `owner` is not authentication.
- `AetherWebPrimitives` overlaps Agent 3's actual Promise and event-loop machinery. No unproven second queue.
- `AetherRenderInfrastructure` overlaps the existing full-page design capture and frame diagnostics; capture planning alone does not render.
- `AetherMetalBackend` overlaps `Graphics/MetalRenderer.swift`. It is an unqualified offscreen quad path, not the compositor or macOS-verified GPU solution.

## Outstanding correctness and security limits

This is **not** a completed P0–P2 browser engine or a comprehensive security boundary. The existing runtime still has no hardened renderer sandbox. Full HTTP caching requires request variant keys, authorization handling, conditional validation and persistent policy; the conservative cache above intentionally refuses many responses. HSTS must be enforced across all redirects, not just initial requests. Complete Fetch/CORS/CSP enforcement, web standards and production macOS GPU rendering remain independent projects.

Merge only with a reviewed diff, a successful native release build, successful targeted integration tests and benchmark, and an explicit comparison against the existing full-suite failure baseline. The 14 outstanding JavaScript failures must not be described as passing. Do not use a green add-on-only test suite as evidence that the integrated browser works.


## Native Apple Silicon validation and unchanged baseline

The integration branch's native macOS 15 / Swift 6.2+ release build passes. The five targeted `NetworkHardeningIntegrationTests` tests and seven matching network tests pass. `enginebench` completes on the macOS runner. The combined suite runs 172 tests and currently reports 14 JavaScript-runtime issues.

For comparison, the untouched `main` code on `verification/aether-baseline-20260919` (with only test-compilation repairs) ran 165 tests and reported 24 issues. The 14 remaining integration failures concern JavaScript parsing, promises, modules, and Fetch, not the network-hardening change; some original capture and disk-cache failures were corrected during the integration work. This is improvement against a broken baseline, **not a fully green suite or production web compatibility**.

The live integrated modules are the original Aether runtime and its existing persistence, capture, scheduler, agent protocol and graphics modules. The remaining `Sources/EngineAdditions` sources are not silently active: do not imply that their mere presence constitutes integration.
