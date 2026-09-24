# Aether performance stress — 20260924_112728

Binary: `0618949309902c461c81bd531e89d4f1d4350eef76d50b809efb429e17cc0e34`

App launch: 1599.2 ms
Completed: 20/20

| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pass1_01_clay_home | ok | 54.5 | 1609.7 | 1149 | — | https://www.clay.com/ |
| pass1_02_apollo_home | ok | 16.5 | 652.8 | 396 | — | https://www.apollo.io/ |
| pass1_03_awwwards_home | ok | 117.2 | 2603.3 | 1609 | — | https://www.awwwards.com/ |
| pass1_04_land-book_home | ok | 325.3 | 8676.1 | 7619 | — | https://land-book.com/ |
| pass1_05_calendly_home | ok | 40.0 | 1660.2 | 472 | — | https://calendly.com/ |
| pass1_06_wisprflow_home | ok | 35.9 | 798.5 | 375 | — | https://wisprflow.ai/ |
| pass1_07_jack-and-jill_home | ok | 34.0 | 801.7 | 288 | — | https://www.jackandjill.ai/ |
| pass1_08_privy_home | ok | 32.1 | 514.3 | 271 | — | https://www.privy.io/ |
| pass1_09_airtable_home | ok | 28.0 | 1314.9 | 843 | — | https://www.airtable.com/ |
| pass1_10_intercom_home | ok | 56.1 | 1574.2 | 1080 | — | https://www.intercom.com/ |
| pass1_01_clay_route | ok | 101.5 | 2029.1 | 1423 | — | https://www.clay.com/pricing |
| pass1_02_apollo_route | ok | 52.2 | 940.7 | 349 | — | https://www.apollo.io/pricing |
| pass1_03_awwwards_route | ok | 35.5 | 1260.6 | 662 | — | https://www.awwwards.com/websites/art/ |
| pass1_04_land-book_route | ok | 205.0 | 13941.6 | 13508 | — | https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies |
| pass1_05_calendly_route | ok | 18.1 | 1319.2 | 324 | — | https://calendly.com/pricing |
| pass1_06_wisprflow_route | ok | 255.1 | 1197.0 | 354 | — | https://wisprflow.ai/pricing |
| pass1_07_jack-and-jill_route | ok | 74.2 | 548.6 | 215 | — | https://www.jackandjill.ai/pricing |
| pass1_08_privy_route | ok | 46.8 | 677.4 | 224 | — | https://www.privy.io/careers-old |
| pass1_09_airtable_route | ok | 36.8 | 838.7 | 533 | — | https://www.airtable.com/solutions/enterprise |
| pass1_10_intercom_route | ok | 60.6 | 833.8 | 441 | — | https://www.intercom.com/customers |

Successful loads: median 1228.8 ms; p95 8676.1 ms; worst 13941.6 ms.

| Metric | Samples | Median ms | p95 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| dispatchMs | 20 | 49.5 | 255.1 | 325.3 |
| toReadyMs | 20 | 1228.8 | 8676.1 | 13941.6 |
| navigationStartDelayMs | 20 | 226.0 | 820.0 | 1024.8 |
| requestStartMs | 20 | 11.0 | 200 | 771 |
| responseStartMs | 20 | 67.5 | 903 | 1131 |
| responseEndMs | 20 | 150.5 | 7028 | 13256 |
| fcpMs | 20 | 456.5 | 7619 | 13508 |
| lcpMs | 0 | None | None | None |
| domContentLoadedMs | 20 | 450.5 | 1551 | 13521 |
| loadEventEndMs | 6 | 582.0 | 13711 | 13711 |

Ready requires the Aether ready state and reported FCP for the current document. FCP/LCP use the document navigation clock; ready time includes command dispatch and polling. Screenshots are captured after timing.
