# Aether before/after (YouTube, Aether only)

Each sample uses a fresh temporary profile; order alternates before/after. URLs: YouTube home and results. No Chrome/Dia processes are launched.

| Action | Metric | Before median ms | After median ms | Change |
App launch ready median: before None ms; after None ms.
| --- | --- | ---: | ---: | ---: |
| cold_navigation | dispatchMs | 28.6 | 17.5 | -11.1 ms (-38.8%) |
| cold_navigation | toReadyMs | 1334.4 | 1597.9 | +263.5 ms (+19.7%) |
| cold_navigation | toFCPMs | 881.6 | 1507.8 | +626.2 ms (+71.0%) |
| cold_navigation | paintToReadyMs | 52.1 | 90.1 | +38.0 ms (+72.9%) |
| warm_navigation | dispatchMs | 10.2 | 15.9 | +5.7 ms (+55.9%) |
| warm_navigation | toReadyMs | 1825.9 | 1221.7 | -604.2 ms (-33.1%) |
| warm_navigation | toFCPMs | 1637.9 | 1143.8 | -494.1 ms (-30.2%) |
| warm_navigation | paintToReadyMs | 247.7 | 82.4 | -165.3 ms (-66.7%) |
| back | dispatchMs | 17.5 | 16.6 | -0.9 ms (-5.1%) |
| back | toReadyMs | 955.5 | 1265.9 | +310.4 ms (+32.5%) |
| back | toFCPMs | 737.1 | 1226.3 | +489.2 ms (+66.4%) |
| back | paintToReadyMs | 174.9 | 39.6 | -135.3 ms (-77.4%) |
| forward | dispatchMs | 15.3 | 10.2 | -5.1 ms (-33.3%) |
| forward | toReadyMs | 73.5 | 1102.5 | +1029.0 ms (+1400.0%) |
| forward | toFCPMs | 1113.2 | 970.4 | -142.8 ms (-12.8%) |
| forward | paintToReadyMs | 153.2 | 197.0 | +43.8 ms (+28.6%) |
| new_tab | dispatchMs | 20.7 | 15.6 | -5.1 ms (-24.6%) |
| new_tab | toReadyMs | 1822.0 | 1069.8 | -752.2 ms (-41.3%) |
| new_tab | toFCPMs | 988.1 | 1103.7 | +115.6 ms (+11.7%) |
| new_tab | paintToReadyMs | 213.2 | 283.9 | +70.7 ms (+33.2%) |
