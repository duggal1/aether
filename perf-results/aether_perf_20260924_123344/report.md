# Aether performance stress — 20260924_123344

Binary: `352a711be8deef595776845f0bc21aef6b0d41c6ecef6e3c858061d68255b353`

App launch: 1380.3 ms
Completed: 10/10

| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pass1_01_jack-and-jill_home | ok | 57.9 | 946.7 | 250 | — | https://www.jackandjill.ai/ |
| pass1_01_jack-and-jill_route | ok | 18.9 | 231.7 | 96 | — | https://www.jackandjill.ai/pricing |
| pass2_01_jack-and-jill_home | ok | 15.3 | 400.3 | 134 | — | https://www.jackandjill.ai/ |
| pass2_01_jack-and-jill_route | ok | 50.2 | 311.1 | 122 | — | https://www.jackandjill.ai/pricing |
| pass3_01_jack-and-jill_home | ok | 20.1 | 271.2 | 105 | — | https://www.jackandjill.ai/ |
| pass3_01_jack-and-jill_route | ok | 92.3 | 319.3 | 123 | — | https://www.jackandjill.ai/pricing |
| pass4_01_jack-and-jill_home | ok | 25.4 | 474.0 | 268 | — | https://www.jackandjill.ai/ |
| pass4_01_jack-and-jill_route | ok | 17.7 | 240.0 | 114 | — | https://www.jackandjill.ai/pricing |
| pass5_01_jack-and-jill_home | ok | 22.4 | 309.0 | 125 | — | https://www.jackandjill.ai/ |
| pass5_01_jack-and-jill_route | ok | 20.6 | 254.3 | 128 | — | https://www.jackandjill.ai/pricing |

Successful loads: median 310.1 ms; p95 946.7 ms; worst 946.7 ms.

| Metric | Samples | Median ms | p95 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| dispatchMs | 10 | 21.5 | 92.3 | 92.3 |
| toReadyMs | 10 | 310.1 | 946.7 | 946.7 |
| navigationStartDelayMs | 10 | 49.2 | 509.7 | 509.7 |
| requestStartMs | 10 | 0.0 | 0 | 0 |
| responseStartMs | 10 | 0.0 | 0 | 0 |
| responseEndMs | 10 | 90.0 | 200 | 200 |
| fcpMs | 10 | 124.0 | 268 | 268 |
| lcpMs | 0 | None | None | None |
| domContentLoadedMs | 10 | 90.0 | 255 | 255 |
| loadEventEndMs | 10 | 142.5 | 352 | 352 |

Ready requires the Aether ready state and reported FCP for the current document. FCP/LCP use the document navigation clock; ready time includes command dispatch and polling. Screenshots are captured after timing.
