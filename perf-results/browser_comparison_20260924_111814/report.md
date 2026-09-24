# Browser comparison: one visit per URL

Twenty URLs per browser, in homepage batch then route batch. One benchmark window and tab per browser; browsers run sequentially. Timing starts before AppleScript navigation and ends when the current document reports FCP.

| Browser | Completed | Median observed FCP ms | p95 observed FCP ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| chrome | 0/20 | None | None | None |
| dia | 0/20 | None | None | None |
| safari | 0/20 | None | None | None |

| Browser | Site | Page | Status | Observed FCP ms | Document FCP ms | Final URL / error |
| --- | --- | --- | --- | ---: | ---: | --- |
| chrome | clay | home | failed | — | — | 152:216: execution error: Google Chrome got an error: Executing JavaScript through AppleScript is turned off. To turn it on, from the menu bar, go to View > Developer > Allow JavaScript from Apple Events. For more information: https://support.google.com/chrome/?p=applescript (12) |
| safari | clay | home | failed | — | — | 141:204: execution error: Safari got an error: You must enable 'Allow JavaScript from Apple Events' in the Developer section of Safari Settings to use 'do JavaScript'. (8) |

Observed FCP includes AppleScript dispatch and polling. Document FCP uses the page's navigation clock. Screenshots are captured after timing. Automation overhead differs from Aether's browserctl path; compare page metrics and images, not the observed wall times alone.
