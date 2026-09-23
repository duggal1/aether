# Aether performance stress — 20260923_235951

Binary: `c6a9b01ccdbacc16421f5ffe18d69b161fed0a3d6c83666ba6ad0851af648739`

App launch: 1294.8 ms
Completed: 20/20

| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pass1_01_clay_home | ok | 65.8 | 1564.5 | 1054 | — | https://www.clay.com/ |
| pass1_02_apollo_home | ok | 12.6 | 497.2 | 308 | — | https://www.apollo.io/ |
| pass1_03_awwwards_home | ok | 13.6 | 2223.8 | 928 | — | https://www.awwwards.com/ |
| pass1_04_land-book_home | ok | 26.5 | 1470.5 | 1062 | — | https://land-book.com/ |
| pass1_05_calendly_home | ok | 20.5 | 1367.6 | 216 | — | https://calendly.com/ |
| pass1_06_wisprflow_home | ok | 51.8 | 691.7 | 301 | — | https://wisprflow.ai/ |
| pass1_07_jack-and-jill_home | ok | 36.4 | 899.5 | 347 | — | https://www.jackandjill.ai/ |
| pass1_08_privy_home | ok | 48.4 | 1339.7 | 439 | — | https://www.privy.io/ |
| pass1_09_airtable_home | ok | 26.4 | 1384.0 | 819 | — | https://www.airtable.com/ |
| pass1_10_intercom_home | ok | 48.7 | 1810.5 | 1352 | — | https://www.intercom.com/ |
| pass1_01_clay_route | ok | 19.8 | 1354.9 | 1061 | — | https://www.clay.com/pricing |
| pass1_02_apollo_route | ok | 23.5 | 739.4 | 395 | — | https://www.apollo.io/pricing |
| pass1_03_awwwards_route | ok | 16.1 | 1372.1 | 907 | — | https://www.awwwards.com/websites/art/ |
| pass1_04_land-book_route | ok | 23.4 | 1849.5 | 1585 | — | https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies |
| pass1_05_calendly_route | ok | 20.4 | 1232.6 | 225 | — | https://calendly.com/pricing |
| pass1_06_wisprflow_route | ok | 19.3 | 538.2 | 246 | — | https://wisprflow.ai/pricing |
| pass1_07_jack-and-jill_route | ok | 21.7 | 13647.9 | 13241 | — | https://www.jackandjill.ai/pricing |
| pass1_08_privy_route | ok | 53.1 | 555.3 | 197 | — | https://www.privy.io/careers-old |
| pass1_09_airtable_route | ok | 78.4 | 1243.0 | 861 | — | https://www.airtable.com/solutions/enterprise |
| pass1_10_intercom_route | ok | 49.6 | 717.7 | 422 | — | https://www.intercom.com/customers |

Successful loads: median 1347.3 ms; p95 2223.8 ms; worst 13647.9 ms.

| Metric | Samples | Median ms | p95 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| dispatchMs | 20 | 24.9 | 65.8 | 78.4 |
| toReadyMs | 20 | 1347.3 | 2223.8 | 13647.9 |
| navigationStartDelayMs | 20 | 141.4 | 871.5 | 892.2 |
| responseStartMs | 20 | 107.0 | 866 | 12196 |
| fcpMs | 20 | 629.0 | 1585 | 13241 |
| lcpMs | 0 | None | None | None |
| domContentLoadedMs | 20 | 476.0 | 1682 | 13177 |
| loadEventEndMs | 6 | 883.5 | 13224 | 13224 |

Ready requires the Aether ready state and reported FCP for the current document. FCP/LCP use the document navigation clock; ready time includes command dispatch and polling. Screenshots are captured after timing.
