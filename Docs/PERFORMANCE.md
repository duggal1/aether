# Performance

Performance is treated as correctness. Claims must come from benchmarks and profiles, not from language choice or GPU marketing.

The optimization order is:

1. Avoid work.
2. Reuse work.
3. Invalidate only affected state.
4. Parallelize independent work.
5. Move raster/composition work to the GPU when it belongs there.

## Current mechanisms

- Compact typed identifiers instead of stringly-typed cross-module state
- Generational DOM slots and bounded mutation history
- Interned atoms for repeated engine strings
- Streaming HTML parsing rather than requiring a second full-document representation
- Parallel external stylesheet and image loading
- Ordered script loading to preserve document semantics
- Bounded HTTP cache and isolated per-context network state
- Display lists separating page construction from rendering targets
- Dirty-region representation ready for narrower repaint work
- Swift structured concurrency for independent I/O rather than thread-per-resource behavior
- Metal foundation on macOS and deterministic software rendering for headless/test paths
- Metrics for network, parse, style, layout, display-list, render, DOM-node, command, and response-byte costs

## Rules for continuation

Do not parallelize dependent layout work merely to increase task count. Do not move HTML/CSS parsing to Metal. Do not retain decoded resources without eviction policy once persistent browsing workloads are introduced. Do not keep every logical agent page fully live when freezing/serialization can release expensive renderer state.

Before optimizing an implementation, preserve a regression fixture and record the before/after benchmark. Memory, p95 interaction latency, navigation latency, frame cost, unnecessary layout work, texture residency, and background-page cost should eventually become release gates.
