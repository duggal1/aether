# Headless comparison — 20260925_185953 (zero windows, zero focus theft)

| Browser | Completed | Load complete | Median dispatch ms | Median ready ms | Median load ms | Median FCP ms | p95 ready | Worst ready |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| aether/cold | 2/2 | 2 | 902.3 | 1703.6 | 3094.4 | 456.0 | 2058.9 | 2058.9 |
| aether/warm | 6/6 | 6 | 245.2 | 737.8 | 1274.1 | 604.0 | 2245.9 | 2245.9 |
| chrome/cold | 2/2 | 2 | 239.8 | 767.5 | 1468.6 | 676.0 | 864.8 | 864.8 |
| chrome/warm | 6/6 | 6 | 216.8 | 1223.0 | 1065.7 | 1066.0 | 1545.9 | 1545.9 |
| dia/cold | 0/2 | 0 | None | None | None | None | None | None |
| dia/warm | 0/6 | 0 | None | None | None | None | None | None |


Safari-engine proxy (offscreen raw WKWebView; not Safari.app):

| Mode | FCP samples | Median FCP ms | p95 FCP ms | Median action-to-FCP ms | Loads complete |
| --- | ---: | ---: | ---: | ---: | ---: |
| cold | 6 | 666.0 | 1746 | 1202.4 | 6/6 |
| warm | 5 | 740 | 1134 | 852.0 | 6/6 |

Dia did not provide a usable headless CDP session; no headed fallback was run.


## Interpretation

Document FCP medians on YouTube were 456 ms cold and 604 ms warm for Aether, 676 ms cold and 1,066 ms warm for Chrome headless, and 666 ms cold and 740 ms warm for the detached WKWebView proxy. These are small samples across the home page and search results; warm FCP had an Aether 2,217 ms outlier.

Aether's cold dispatch includes creation of a fresh browser context and WebView. Chrome's timing starts from a prepared blank headless tab, so action-to-FCP and dispatch are not a fair cold-start comparison. The document FCP values are measured from each document's own navigation start.

Dia 1.49.1 did not maintain a headless CDP session (connection reset); no headed fallback was used. Safari 27.0 was not launched; its row is a raw, detached WKWebView engine proxy, not a Safari.app measurement. No scrolling, click-success, CPU, GPU, or memory comparison was collected.

Aether release hashes: browserd 4b39abadafe53809770dbbea47befd8ade6dd133f1b874406c608ce112c5ce7a, packaged AetherApp 58ac0c6485dcdc484a8e52fca78f92dab87b3b2b2d31adbdd56ec6181c2cdf7a.
