# Aether performance stress — 20260924_114218

Binary: `d2ea7d7bca8ec33dbbc6cd09fccd58d8dc484870a7770e98f08678d8ce6af047`

App launch: 1381.9 ms
Completed: 10/10

| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pass1_01_jack-and-jill_home | ok | 147.8 | 1003.5 | 233 | — | https://www.jackandjill.ai/ |
| pass1_01_jack-and-jill_route | ok | 20.3 | 537.6 | 287 | — | https://www.jackandjill.ai/pricing |
| pass2_01_jack-and-jill_home | ok | 14.5 | 433.3 | 135 | — | https://www.jackandjill.ai/ |
| pass2_01_jack-and-jill_route | ok | 113.5 | 307.9 | 98 | — | https://www.jackandjill.ai/pricing |
| pass3_01_jack-and-jill_home | ok | 20.3 | 257.2 | 118 | — | https://www.jackandjill.ai/ |
| pass3_01_jack-and-jill_route | ok | 42.1 | 231.5 | 95 | — | https://www.jackandjill.ai/pricing |
| pass4_01_jack-and-jill_home | ok | 14.1 | 230.1 | 116 | — | https://www.jackandjill.ai/ |
| pass4_01_jack-and-jill_route | ok | 16.1 | 306.0 | 106 | — | https://www.jackandjill.ai/pricing |
| pass5_01_jack-and-jill_home | ok | 38.7 | 253.9 | 110 | — | https://www.jackandjill.ai/ |
| pass5_01_jack-and-jill_route | ok | 40.1 | 270.5 | 97 | — | https://www.jackandjill.ai/pricing |

Successful loads: median 288.2 ms; p95 1003.5 ms; worst 1003.5 ms.

| Metric | Samples | Median ms | p95 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| dispatchMs | 10 | 29.5 | 147.8 | 147.8 |
| toReadyMs | 10 | 288.2 | 1003.5 | 1003.5 |
| navigationStartDelayMs | 10 | 59.0 | 598.9 | 598.9 |
| requestStartMs | 10 | 0.0 | 0 | 0 |
| responseStartMs | 10 | 0.0 | 0 | 0 |
| responseEndMs | 10 | 85.0 | 265 | 265 |
| fcpMs | 10 | 113.0 | 287 | 287 |
| lcpMs | 0 | None | None | None |
| domContentLoadedMs | 10 | 85.0 | 265 | 265 |
| loadEventEndMs | 7 | 143 | 337 | 337 |

Ready requires the Aether ready state and reported FCP for the current document. FCP/LCP use the document navigation clock; ready time includes command dispatch and polling. Screenshots are captured after timing.
