# Aether perf stress — 20260923_225502

App: `.build/Aether.app`
Binary sha256: `8e1cf51d87c8489a8a41314f0488fe7834c0de445d4d3f8b4fad487ef8c78f6a`

| step | dispatch_ms | to_ready_ms | title |
| --- | --- | --- | --- |
| cold_launch_to_ready | - | 7711.5 | https://www.clay.com/ |
| warm_open:https://clay.com/ | 0.0 | 1813.2 | https://www.clay.com/ |
| route:https://clay.com/pricing | 37.4 | 829.9 | Compare plans, features & costs | Clay.com |
| back | 16.6 | 248.7 | https://www.clay.com/ |
| forward | 20.0 | 110.7 | https://www.clay.com/pricing |
| reload | 13.5 | 94.7 | Compare plans, features & costs | Clay.com |

median_to_ready=539.3ms mean=1801.5ms min=94.7ms max=7711.5ms
