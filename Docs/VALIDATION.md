# Validation

The distributed Engine 0 snapshot was validated with Swift 6.2.1 on the available build host.

## Automated suite

```text
swift test
27 tests passed
0 failures
```

Coverage includes HTML streaming/raw-text behavior, DOM generations/mutations/selectors, CSS parsing, layout including form controls, software rendering including decoded-image compositing, network cookie/cache behavior, JavaScript closures/DOM/events/localStorage, storage partitioning, origin handling, agent dispatcher lifecycle, and a 10,000-node pipeline test.

## Release build

```text
swift build -c release
Build complete
No compiler warnings observed
```

## Benchmark harness

One release run on the build host:

```text
nodes=50006
parse_ms=421.944826
style_ms=181.224648
layout_ms=121.166031
boxes=50003
```

These numbers are a regression baseline for this host, not a cross-machine performance claim.

## End-to-end local agent smoke test

A persistent `browserd` session was exercised against a local HTTP fixture through `browserctl`:

```text
ping → success
context.create → success
page.create + page.navigate → success
page.query textbox/button → success
page.setValue alpha → beta → success
page.evaluate localStorage.getItem("loaded") → yes
page.render 1280×800 → success
page.click submit → navigated to /next.html?q=beta&go=1
page.back → restored index.html with forward history
page.metrics → success
```

The generated offscreen frame was 1280×800.

## Platform qualification boundary

The available validation host is `x86_64-unknown-linux-gnu`. macOS-only Metal, CoreText, CoreGraphics, ImageIO, VideoToolbox, future `CAMetalLayer`, and sandbox behavior cannot be truthfully qualified from that host. Those code paths must be built, tested, and profiled on Apple Silicon before making production macOS GPU or memory claims.

Engine 0 is also not a hardened sandbox for hostile web content. Security isolation remains explicit continuation work rather than a hidden assumption.
