# Jev search: conclusion

## What was built

A new leaf target `Sources/JevSearch` implementing search intelligence on TypeSafe's Jev (System One) model, with Search1API retrieval and Google as the fallback, wired through the single `BrowserRuntime` and surfaced in the native UI.

## Evidence

- `swift test --filter JevSearchTests`: 30 tests in 6 suites pass.
- `JEV_LIVE=1 swift test --filter JevLiveTests`: 4 tests pass against the real services.
- `Sources/BrowserUI`: build clean, 0 warnings; `AddressResolverTests` 12 tests pass.
- Full release build of `AetherApp`, `browserctl`, `browserd`, `enginebench`: 0 errors, 0 warnings.
- Both API contracts came from primary sources, not memory: TypeSafe's request/response shapes from `Aether/docs/jev/doc.md`, and Search1API's body and result fields from `https://s1.dev/docs/basic/search`.

Real service output:

```
model=jev-1.13.0 intent=informational confidence=1.0 retrieved=7 answers=9 degraded=false
[web] score=2.75 rel=0.98 TaskGroup | Apple Developer Documentation
[web] score=2.75 rel=0.98 TaskGroup and Structured Concurrency Patterns in Swift
apple  intent=navigational confidence=0.66 primary=https://apple.com
```

## What live verification caught that tests could not

Two real defects, both invisible to folder-and-fixture tests:

1. **Timeout too tight.** 8s was fine for a single search engine and too tight for Search1API's multi-engine fused retrieval, which timed out for real. Default is now 15s.
2. **Ranking weights were wrong.** An 0.37-relevance bookmark outranked 0.98-relevance web results because the local tier carried a fixed base bonus that relevance could not overcome. Relevance now weighs 2.5 in both retrieval tiers and the local bonus is only 0.5 higher than the web bonus, so tier dominance is earned by the model's judgment rather than assumed by the tier.

Both are examples of why the live suite exists and should be run after any change to ranking or transport.

## Design decisions that mattered

- The user's request arrived with an analysis of a third-party "Jev Search" app whose recommended fix was to add a provider case that navigates the address bar to a website. That would have produced no intelligence at all. The user's own docs describe Jev as a decision model that cannot retrieve the web, so the built shape is: deterministic classification and ranking in code, Search1API for retrieval, Jev for intent, candidate generation and relevance.
- `SEARCH1API_SERVICE` is never defaulted. Omitting it from the request body is what enables multi-engine fused retrieval; defaulting to `"google"` would have silently reduced retrieval to one engine.
- "Say Apple, it's a .com" is a real model judgment, not string concatenation: candidates are generated in code, judged by a Jev `choice`, validated against the generated set to stop prompt drift creating an arbitrary host, and pinned only above the 0.6 confidence floor.
- Google is the fallback rather than a competitor: appended when Jev cannot serve or when nothing survives relevance filtering, using the browser-identity fix so Google genuinely returns results.

## Known gaps

1. **The omnibox dropdown does not consult Jev while typing.** `SearchIntelligence.completions` is implemented, tested and cached per token, but `OmniboxSuggestionModel` still uses the local/provider path. This is the largest remaining piece of the user's ask.
2. No agent-protocol exposure; reachable via `BrowserRuntime.jevSearch`, so adding `AgentMethod` cases plus a `browserctl` subcommand is mechanical.
3. No summarisation stage. Jev does not generate text; do not present `relevance` as factual confidence.
4. A transient retrieval timeout degrades to the Google fallback rather than retrying.

## Repository lessons

- `.env` is now git-ignored with `.env.example` committed; the repository previously had no environment-secret convention. `JEV_LIVE=1` gates any test that spends real API credits, so the default suite stays free and offline.
- `BrowserRuntime` owns everything and `AetherHumanUI` must never import an engine module. New engine capability reaches the UI as a `@MainActor` port protocol plus UI-side value types implemented in `AetherApp`. The boundary is enforced by build failure.
- Live third-party verification is worth the credits: it found two defects that 30 passing unit tests did not.
