# Aether performance stress — 20260923_234819

Binary: `b7f0d512511a9ff460538b9c522e074da5b8e461d7da8afb29823d6ed55860f9`

App launch: 1895.4 ms
Completed: 20/20

| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pass1_01_clay_home | ok | 59.2 | 1758.9 | 1085 | — | https://www.clay.com/ |
| pass1_02_apollo_home | ok | 11.4 | 599.7 | 371 | — | https://www.apollo.io/ |
| pass1_03_awwwards_home | ok | 25.1 | 2214.7 | 866 | — | https://www.awwwards.com/ |
| pass1_04_land-book_home | ok | 50.0 | 1485.5 | 997 | — | https://land-book.com/ |
| pass1_05_calendly_home | ok | 20.0 | 809.1 | 251 | — | https://calendly.com/ |
| pass1_06_wisprflow_home | ok | 22.6 | 1485.0 | 441 | — | https://wisprflow.ai/ |
| pass1_07_jack-and-jill_home | ok | 58.5 | 793.1 | 379 | — | https://www.jackandjill.ai/ |
| pass1_08_privy_home | ok | 39.7 | 632.5 | 326 | — | https://www.privy.io/ |
| pass1_09_airtable_home | ok | 61.3 | 2212.1 | 1755 | — | https://www.airtable.com/ |
| pass1_10_intercom_home | ok | 21.0 | 1814.6 | 1396 | — | https://www.intercom.com/ |
| pass1_01_clay_route | ok | 33.1 | 2510.1 | 2003 | — | https://www.clay.com/pricing |
| pass1_02_apollo_route | ok | 19.3 | 609.2 | 280 | — | https://www.apollo.io/pricing |
| pass1_03_awwwards_route | ok | 19.9 | 2192.1 | 1040 | — | https://www.awwwards.com/websites/art/ |
| pass1_04_land-book_route | ok | 67.2 | 2004.4 | 1492 | — | https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies |
| pass1_05_calendly_route | ok | 17.9 | 1308.0 | 344 | — | https://calendly.com/pricing |
| pass1_06_wisprflow_route | ok | 33.0 | 840.7 | 311 | — | https://wisprflow.ai/pricing |
| pass1_07_jack-and-jill_route | ok | 26.5 | 1060.3 | 775 | — | https://www.jackandjill.ai/pricing |
| pass1_08_privy_route | ok | 30.1 | 954.9 | 285 | — | https://www.privy.io/careers-old |
| pass1_09_airtable_route | ok | 28.9 | 873.8 | 557 | — | https://www.airtable.com/solutions/enterprise |
| pass1_10_intercom_route | ok | 28.7 | 1090.0 | 526 | — | https://www.intercom.com/customers |

Successful loads: median 1199.0 ms; p95 2214.7 ms; worst 2510.1 ms.

| Metric | Samples | Median ms | p95 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| dispatchMs | 20 | 28.8 | 61.3 | 67.2 |
| toReadyMs | 20 | 1199.0 | 2214.7 | 2510.1 |
| navigationStartDelayMs | 20 | 183.3 | 840.1 | 848.7 |
| responseStartMs | 20 | 60.0 | 640 | 643 |
| fcpMs | 20 | 541.5 | 1755 | 2003 |
| lcpMs | 0 | None | None | None |
| domContentLoadedMs | 20 | 459.5 | 1507 | 1791 |
| loadEventEndMs | 4 | 757.5 | 1837 | 1837 |

Ready requires the Aether ready state and reported FCP for the current document. FCP/LCP use the document navigation clock; ready time includes command dispatch and polling. Screenshots are captured after timing.
