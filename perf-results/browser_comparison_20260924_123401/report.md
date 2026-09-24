# Browser comparison

5 pass(es) of 2 URLs per browser; each homepage immediately before its route. One benchmark window and tab per browser; browsers run sequentially. Timing starts before AppleScript navigation and ends when the current document reports FCP.

| Browser | Completed | Median observed FCP ms | p95 observed FCP ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| chrome | 0/10 | None | None | None |
| dia | 0/10 | None | None | None |
| safari | 0/10 | None | None | None |

| Browser | Site | Page | Status | Observed FCP ms | Document FCP ms | Final URL / error |
| --- | --- | --- | --- | ---: | ---: | --- |

Observed FCP includes AppleScript dispatch and polling. Document FCP uses the page's navigation clock. Screenshots are captured after timing. Automation overhead differs from Aether's browserctl path; compare page metrics and images, not the observed wall times alone.
