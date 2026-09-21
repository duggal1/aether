# Google search + AI Mode: conclusion

## What was actually wrong

The reported "search never reaches results" failure was **not** a wrong URL and **not** an outdated engine. The search URL was already correct. The client identity was wrong.

`Sources/EngineRuntime/WebKit/WebKitAppearance.swift` was a no-op:

```swift
enum WebKitAppearance {
  @MainActor static func install(in configuration: WKWebViewConfiguration) {
  }
}
```

So the one and only `WKWebView` construction site (`WebKitPage.init`, `WebKitPage.swift:61-66`) sent WebKit's bare default user agent:

```
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)
```

No `Version/… Safari/…` token, no browser identity. Google treated the client as not-a-browser and declined to serve a normal results document.

Reproduced with `browserctl eval` / `browserctl shell` (same `WebKitPage` + `WKWebView` stack the app uses), against live Google:

| Input | Bare WebKit UA (before) | With browser identity (after) |
| --- | --- | --- |
| `/search?q=swift` | 0 links, title `Google Search`, body is the `<noscript>` meta-refresh to `/httpservice/retry/enablejs` ("if you are not redirected within a few seconds") | **134 links**, real results |
| `/ai` | bounced to `webhp?aep=11` | resolves to **`/search?udm=50&aep=11`** |
| `/search?udm=50&q=swift` | `udm=50` **stripped** → `/search?q=swift` | `udm=50` **preserved**, hydrates with `mstk=`/`csuir=1`, 32 links |

That single fact explains all three reported symptoms: no results, "never redirects to the Google search result", and "AI Mode not hooked up at all".

Controls that ruled out other explanations:

- Google's homepage loaded fine (`Google`, 20 links, 1 form) — so this was not a blanket WebKit/networking failure.
- DuckDuckGo (130 links) and Bing (107 links) returned full results — so it was Google-`/search`-specific.
- A control page proved page-level JavaScript **does** execute in Aether's WKWebView (`document.title` became `JS-RAN`), and `typeof google === "object"` on the interstitial, so Google's own script ran. The decision was made server-side, on the request fingerprint.
- Generic vs full-Safari UA via `curl` returned the same interstitial, but curl cannot execute JavaScript, so UA was not settled by that test — only by re-running the real WKWebView.

## Fix

- `WebKitAppearance` now installs a real browser identity on the single `WKWebView` configuration: `applicationNameForUserAgent = "Version/<OS major>.0 Safari/605.1.15"`, with content JavaScript explicitly enabled.
- `BrowserUI/Foundation/AddressResolver.swift` builds search URLs with `URLComponents`/`URLQueryItem` instead of concatenating `template + manuallyPercentEncodedText`, and gains per-provider `homepage` / `searchEndpoint` / `searchURL(for:)`. `.googleAI` routes to `search?udm=50&q=`.
- The omnibox AI Mode button reads `SearchProvider.googleAI.homepage` instead of an inline literal, so chrome and provider configuration cannot diverge.
- Persisted `rawValue` strings were deliberately left unchanged; `aether.provider` values in `UserDefaults` keep resolving.

## Verification

- `swift build -c release` (all products, including `AetherApp`): green.
- `Sources/BrowserUI`: `swift build` clean, 0 warnings; `swift test` — 34/35 pass, including 10/10 new `AddressResolverTests` (URL shape, AI Mode routing, exact `&`/`+`/`#`/`?`/`%`/unicode query round-trip, homepages, persisted provider identity stability).
- Live end-to-end at the exact URLs the resolver now produces: `/search?q=swift%20programming` → `swift programming - Google Search`, 97 links, hydrated with `&sei=`; `/search?udm=50&q=swift%20programming` → `udm=50` preserved, hydrated with `mstk=`/`csuir=1`, 40 links.

## Remaining uncertainty

- I could not reproduce the literal "audio robot page" the user described. What I reproduced exactly is Google's interstitial whose own text is "if you are not redirected within a few seconds" — the reported "never redirects to the Google search result". A reCAPTCHA-with-audio interstitial is consistent with "Google refused this client", and the trigger (no browser identity) is now removed, but the audio page itself was not observed.
- Google `/search` commits a JavaScript bootstrap before the results document exists (0 links immediately after commit; full results after several seconds of hydration). Nothing in the current UI cancels hydration — `AetherEngineAdapter.activate` only restores non-live content and does not re-navigate — but this is a fragile boundary worth preserving: any future re-issue of navigation during a Google load will return the user to the interstitial.
- `udm=50` and `aep=11` are Google web-interface parameters, not a versioned API. They are Google-controlled and can change without notice.

## Pre-existing, unrelated

`DesignSystemTests.progressPaletteOffersFourHues` fails (`AetherProgressColor.allCases.count == 4`, but the enum now has only `neutral`). `AetherPalette.swift` was already modified in the working tree before this task and is untouched by this change.
