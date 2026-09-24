# Aether performance stress — 20260924_123330

Binary: `352a711be8deef595776845f0bc21aef6b0d41c6ecef6e3c858061d68255b353`

App launch: 2092.3 ms
Completed: 2/2

| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pass1_01_jack-and-jill_home | ok | 84.3 | 1203.0 | 293 | — | https://www.jackandjill.ai/ |
| pass1_01_jack-and-jill_route | ok | 20.1 | 613.5 | 357 | — | https://www.jackandjill.ai/pricing |

Successful loads: median 908.2 ms; p95 1203.0 ms; worst 1203.0 ms.

| Metric | Samples | Median ms | p95 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| dispatchMs | 2 | 52.2 | 84.3 | 84.3 |
| toReadyMs | 2 | 908.2 | 1203.0 | 1203.0 |
| navigationStartDelayMs | 2 | 348.6 | 623.5 | 623.5 |
| requestStartMs | 2 | 10.0 | 15 | 15 |
| responseStartMs | 2 | 39.5 | 45 | 45 |
| responseEndMs | 2 | 206.0 | 326 | 326 |
| fcpMs | 2 | 325.0 | 357 | 357 |
| lcpMs | 0 | None | None | None |
| domContentLoadedMs | 2 | 323.5 | 345 | 345 |
| loadEventEndMs | 2 | 414.0 | 442 | 442 |

Ready requires the Aether ready state and reported FCP for the current document. FCP/LCP use the document navigation clock; ready time includes command dispatch and polling. Screenshots are captured after timing.
