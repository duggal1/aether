# Aether WebKit performance

Scope: preserve navigation readiness, DOM/node identity, UI observations, and page rendering. Optimize runtime overhead under concurrency. Do not change UI, content blocking, or WebKit rendering policy. All tests and benchmarks run after implementation, as requested. Existing edits are preserved in before/.

1. Skip page-state projection when nobody subscribes, seed observation cache on subscription, and publish just the changed page for WebKit callbacks. Preserve full publication for structural/context mutations.
2. Execute DOM preparation and query/snapshot/action in one isolated-world JavaScript evaluation, keeping generation and stale-node checks.
3. Suppress SIGPIPE per socket on Darwin and per send on Linux so cancelled clients cannot kill the browser daemon.
4. Add regression coverage for state publication and DOM behavior; run bounded tests and serialized release build. Reproduce abandoned-client behavior against the saved Aether binary and verify the candidate. Benchmark local concurrent navigation/inspection and the supplied unchanged 16-site sequential harness (32 trials), Aether only.
5. Save measured results, review diffs against the captured working tree, document limitations. Public-site dispatch-to-title is not paint time; compare historical results cautiously because their daemon restarted 31 times and host/network conditions differ.

Evidence: contexts.didSet projects every page on every mutation; receiveWebState writes contexts for every WebKit event. query/snapshot/nodeAction each make two evaluateJavaScript round trips. UnixSocket.writeAll uses send(...,0) without SO_NOSIGPIPE, while benchmark cleanup terminates pending clients. Apple documents SO_NOSIGPIPE returning EPIPE instead of process signal: https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setsockopt.2.html
