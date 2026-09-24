# Aether performance stress — 20260924_112306

Binary: `c70baa19e419c5d766709046aa9d19f17e792f234674e222fdb208a2ad28f783`

App launch: 1004.2 ms
Completed: 20/20

| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pass1_01_clay_home | ok | 78.0 | 1750.4 | 1066 | — | https://www.clay.com/ |
| pass1_02_apollo_home | ok | 16.4 | 1269.7 | 786 | — | https://www.apollo.io/ |
| pass1_03_awwwards_home | ok | 37.4 | 2511.6 | 2121 | — | https://www.awwwards.com/ |
| pass1_04_land-book_home | ok | 61.5 | 6052.0 | 5514 | — | https://land-book.com/ |
| pass1_05_calendly_home | ok | 49.1 | 1412.5 | 146 | — | https://calendly.com/ |
| pass1_06_wisprflow_home | ok | 65.6 | 809.6 | 380 | — | https://wisprflow.ai/ |
| pass1_07_jack-and-jill_home | ok | 38.1 | 1264.5 | 482 | — | https://www.jackandjill.ai/ |
| pass1_08_privy_home | ok | 46.5 | 1192.9 | 372 | — | https://www.privy.io/ |
| pass1_09_airtable_home | ok | 62.4 | 1264.3 | 763 | — | https://www.airtable.com/ |
| pass1_10_intercom_home | ok | 34.2 | 1732.3 | 1446 | — | https://www.intercom.com/ |
| pass1_01_clay_route | ok | 38.2 | 1556.8 | 1099 | — | https://www.clay.com/pricing |
| pass1_02_apollo_route | ok | 59.6 | 774.7 | 275 | — | https://www.apollo.io/pricing |
| pass1_03_awwwards_route | ok | 30.3 | 1911.3 | 1318 | — | https://www.awwwards.com/websites/art/ |
| pass1_04_land-book_route | ok | 66.3 | 4158.9 | 3409 | — | https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies |
| pass1_05_calendly_route | ok | 30.2 | 1151.8 | 179 | — | https://calendly.com/pricing |
| pass1_06_wisprflow_route | ok | 41.4 | 750.0 | 283 | — | https://wisprflow.ai/pricing |
| pass1_07_jack-and-jill_route | ok | 31.8 | 1197.9 | 911 | — | https://www.jackandjill.ai/pricing |
| pass1_08_privy_route | ok | 25.2 | 334.2 | 173 | — | https://www.privy.io/careers-old |
| pass1_09_airtable_route | ok | 38.3 | 1136.3 | 865 | — | https://www.airtable.com/solutions/enterprise |
| pass1_10_intercom_route | ok | 34.9 | 729.3 | 518 | — | https://www.intercom.com/customers |

Successful loads: median 1264.4 ms; p95 4158.9 ms; worst 6052.0 ms.

| Metric | Samples | Median ms | p95 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| dispatchMs | 20 | 38.2 | 66.3 | 78.0 |
| toReadyMs | 20 | 1264.4 | 4158.9 | 6052.0 |
| navigationStartDelayMs | 20 | 199.7 | 786.5 | 973.7 |
| requestStartMs | 20 | 14.5 | 151 | 1195 |
| responseStartMs | 20 | 69.0 | 1070 | 1592 |
| responseEndMs | 20 | 134.0 | 3213 | 5117 |
| fcpMs | 20 | 774.5 | 3409 | 5514 |
| lcpMs | 0 | None | None | None |
| domContentLoadedMs | 20 | 412.5 | 2043 | 5627 |
| loadEventEndMs | 4 | 841.0 | 5685 | 5685 |

Ready requires the Aether ready state and reported FCP for the current document. FCP/LCP use the document navigation clock; ready time includes command dispatch and polling. Screenshots are captured after timing.
