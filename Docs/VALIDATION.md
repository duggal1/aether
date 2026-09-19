# Validation

Validated on the development host: macOS 27.0 (26A5425a), arm64, 8 CPUs, 8 GiB RAM, Apple Swift 6.4 with Command Line Tools (`xcode-select -p` → `/Library/Developer/CommandLineTools`, no full Xcode). The full suite runs there because the CLT Testing macro plugin exists at `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`; `Scripts/test_macos.py` passes it explicitly plus the Testing framework rpaths, runs tests serially, and enforces a process-tree RSS ceiling.

## Automated suite (2026-09-20)

```text
Scripts/test_macos.py (serial, RSS-bounded)
177 tests, 0 failures across 15 targets
~71 s wall, peak process-tree RSS 1.15 GiB
```

Coverage includes HTML streaming/raw-text/tree-construction behavior, DOM generations/mutations/selectors, CSS parsing, layout including form controls, software rendering including decoded-image compositing, network cookie/cache behavior plus the hardened-cache regression tests, JavaScript closures/DOM/events/localStorage/promises/typed arrays/BigInt, storage partitioning, origin handling, agent dispatcher lifecycle, capture planning, and a 10,000-node pipeline test.

The suite previously reported 14 JavaScript-runtime issues; three confirmed defects were fixed this pass (unary minus never negated, top-level lexical declarations not shared across evaluations, and an Int64 overflow trap reachable from pure JS), and the protocol now emits `"result": null` for null results instead of dropping the key.

## Release build

```text
swift build -c release
Build complete (incremental, 61 s)
```

## Benchmark harness

One release run on this host (10,000 generated `.row` divs, ~50,006 nodes):

```text
nodes=50006
parse_ms=279.2
style_ms=109.1
layout_ms=551.3
boxes=50003
```

These numbers are a regression baseline for this host, not a cross-machine performance claim.

## End-to-end local agent smoke test (2026-09-20)

A persistent `browserd` session was exercised through `browserctl --socket` against a local HTTP fixture (`Fixtures/basic.html` served on 127.0.0.1:8765):

```text
ping → {"ok": true, "engine": "NativeBrowserEngine"}
context.create → success
page.create → success
page.navigate → loaded: true, title "Engine Fixture"
page.query "a" → role link, name "Continue", href /next.html, bounds
page.query "input" → result: null (no match; emitted as JSON null)
page.evaluate "-1e20" → "-100000000000000000000"
page.evaluate "let out=0; Promise.resolve(21).then(v => { out = v*2; }); out"
  → immediate 0, then 42 on the next evaluation (microtask checkpoint correct)
page.render 1280×800 → PNG image data, 1280 x 800, 8-bit/color RGBA
page.metrics → domNodes 38, parse 0.57 ms, style 0.34 ms, layout 4.4 ms,
  displayCommands 20, total 17.7 ms
```

## Platform qualification boundary

The engine is **not** a hardened sandbox for hostile web content: no renderer-process isolation, no macOS sandbox profile, no production compositor. HTML/CSS/layout/JavaScript coverage is real but far from web-platform complete. macOS GPU rendering, media, and memory behavior must be qualified with named workloads before production claims.

Engine 0 remains an architectural foundation; see `Docs/IMPLEMENTATION_STATUS.md` for the honest capability table.
