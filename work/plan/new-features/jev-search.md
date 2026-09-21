# Jev search intelligence

Authorised by the user: Jev becomes the browser's search intelligence, keeping Google as a selectable provider and as the fallback. Sources of truth are `Aether/docs/jev/doc.md` and `Aether/docs/jev/planer.md` (TypeSafe System One / Jev).

## What Jev is and is not

Jev is a decision model. `POST https://api.typesafe.ai/v1/systemone`, `model=jev-latest`, bearer `TYPESAFE_API_KEY`. It answers typed questions (`choice`, `score`, `noul`) against a `state` and returns typed answers with `probabilities` and `confidence`. It cannot retrieve the web and does not generate text, so retrieval is a separate dependency (`SEARCH1API_API_KEY`, `POST https://api.search1api.com/search`).

Its own documented search use cases are candidate generation, query-to-candidate relevance scoring, reranking, and intent classification — which is exactly the split implemented here.

## Architecture

The docs' design law is applied literally: code owns control flow and every deterministic rule; Jev supplies only the judgments code cannot make.

```text
typed input
  → deterministic classification (code)          direct URL/domain? → navigate, no model call
  → Jev: intent choice + per-candidate noul      one request, all candidates judged in parallel
  → Search1API retrieval (concurrent)            multi-engine by default
  → Jev: per-result relevance noul               one request
  → ranking + confidence gating (code)           weighted, deduplicated, thresholded
  → native SwiftUI results inside the tab
```

Ranking is code-owned (`SearchTuning`), so relevance shifts are a coefficient change, not a prompt rewrite. Relevance dominates both retrieval tiers; the tier bonus is deliberately small.

| Tier | Score | Meaning |
| --- | --- | --- |
| direct address | 4.0 | classified as a URL in code, the model is never called |
| judged-domain guess | 3.5 + confidence bonus | intent is `navigational` and confidence ≥ 0.6 |
| local signal | 0.8 + relevance × 2.5 + recency × 0.3 + visits × 0.01 | history, bookmarks, open tabs, shortcuts |
| web result | 0.3 + relevance × 2.5 | dropped below `minimumRelevance` (0.25) |
| Google fallback | 0.5, appended last | only when degraded, or when nothing else survived |

Because relevance weighs 2.5 in both tiers and the local bonus is only 0.5 higher than the web bonus, a strongly-judged saved page still outranks a mediocre web result, while a near-perfect web match outranks a loosely-related bookmark. This balance was corrected by live measurement, not by guesswork.

Confidence gating follows the documented pattern: `confidenceFloor = 0.6`, so a domain guess is only pinned when the model both classifies the intent as navigational and clears the floor. A weak judgment degrades to normal results instead of navigating somewhere wrong.

Google is the safety net, not a competitor: when Jev cannot serve (no keys, both stages failed) or when nothing survives relevance filtering, a `Search Google for "…"` candidate is appended so search always has a way forward. That path uses the WebKit browser identity fix already in place, so Google actually returns results.

## Module

`Sources/JevSearch` (new leaf target, no dependencies beyond Foundation):

| File | Responsibility |
| --- | --- |
| `SearchModels.swift` | candidates, intents, local signals, Jev question/answer wire types, `SearchTuning` |
| `JevConfiguration.swift` | `.env` parse/discover, configuration, `HTTPPostTransport` |
| `JevClient.swift` | typed questions → typed answers |
| `Search1APIClient.swift` | retrieval and result model |
| `SearchIntelligence.swift` | the pipeline, ranking, confidence gating, Google fallback, caches |

Wiring, so both faces of the runtime share one implementation: `BrowserRuntime.searchIntelligence` → `JevSearchIntegration.swift` → `JevSearchFacade.swift` → `BrowserSearchIntelligence` port → `AetherEngineAdapter+Jev.swift`. The UI package never imports an engine module; it speaks its own value types.

## Configuration

`.env` at the repository root, git-ignored, read at launch. Template is `.env.example`.

| Key | Purpose |
| --- | --- |
| `TYPESAFE_API_KEY` | Jev intelligence (required for search intelligence) |
| `SEARCH1API_API_KEY` | web retrieval |
| `JEV_MODEL`, `TYPESAFE_ENDPOINT`, `SEARCH1API_ENDPOINT`, `JEV_SEARCH_RESULTS`, `JEV_REQUEST_TIMEOUT` | optional overrides |

`SEARCH1API_SERVICE` is deliberately **not** defaulted and must not be. When it is unset the field is omitted from the request body entirely, which is what enables Search1API multi-engine retrieval with fused rankings. Pinning retrieval to a single engine is opt-in. The request timeout defaults to 15s because multi-engine fused retrieval is slower than a single engine; 8s produced real timeouts under load.

Discovery order: `AETHER_ENV_FILE`, then `.env` walking up from the working directory and from the main bundle. Process environment overrides file values. With no key the app does not fail: results degrade and the Google fallback appears.

## Behaviour

- Front-page search bar: always Jev (`navigateSelected(_:intelligence:)`).
- Omnibox: Jev when the selected provider is Jev, otherwise the chosen provider.
- Default provider is now `Jev`; Google, Google AI Mode, DuckDuckGo, Bing and Brave are unchanged and still selectable.
- Submitting on the front page routes to `TabLoadState.search(query)`, rendered by `JevSearchResultsView`. Clicking a ranked result navigates the existing WebKit page through the normal engine path.

## Verification

Unit, against fakes and fixtures: `swift test --filter JevSearchTests` — 30 tests in 6 suites covering `.env` parsing, configuration keys and defaults, request shape, all three primitive decodes, unconfigured refusal, `max_results` and `search_service` presence/omission, API failure surfacing, direct-address short-circuit with no model call, intent and domain pinning, non-pinning on weak judgment or wrong intent, relevance reranking, irrelevant-result dropping, graceful degradation, completion ordering, per-query retrieval caching, and Google fallback placement.

Live, against the real TypeSafe and Search1API services, gated behind `JEV_LIVE=1` (`Tests/JevSearchTests/JevLiveTests.swift`): all 4 tests pass.

```
model=jev-1.13.0 intent=informational confidence=1.0 retrieved=7 answers=9 degraded=false
[web] score=2.75 rel=0.98 TaskGroup | Apple Developer Documentation
[web] score=2.75 rel=0.98 TaskGroup and Structured Concurrency Patterns in Swift
[web] score=2.72 rel=0.97 Structured Concurrency | Tasks and Task Groups in swift
apple  intent=navigational confidence=0.66 primary=https://apple.com
```

The live run earned its keep twice: it exposed the 8s timeout, and it showed a 0.37-relevance bookmark outranking 0.98-relevance web results under the original weights, which is what produced the corrected table above.

Builds: full release (`AetherApp`, `browserctl`, `browserd`, `enginebench`) and `Sources/BrowserUI` both 0 errors, 0 warnings; `AddressResolverTests` 12 tests pass.

## Open work

1. Live completions in the omnibox dropdown. `SearchIntelligence.completions` is implemented, tested and cached per token (including the judged-domain guess such as "apple" → `apple.com`), but `OmniboxSuggestionModel` still uses the existing local/provider path, so typing does not yet consult Jev. This is the largest remaining piece of the user's ask.
2. Assistant-style summarisation over retrieved results is deliberately absent: Jev does not generate text, and presenting relevance probabilities as factual confidence would be wrong. A separate synthesis stage would be required.
3. Agent exposure (`AgentMethod` + `browserctl` subcommand) is not added; the capability is already reachable through `BrowserRuntime`, so the dispatcher path is mechanical.
4. A transient retrieval timeout currently yields the Google fallback rather than a retry. A single bounded retry would improve resilience.
