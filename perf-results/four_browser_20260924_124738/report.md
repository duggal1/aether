# Four-browser comparison — 20260924_124738

| Browser | Completed | Median ready ms | p95 ms | Worst ms | Method |
| --- | ---: | ---: | ---: | ---: | --- |
| aether | 2/2 | 479.2 | 767.6 | 767.6 | FCP |
| chrome | 0/1 | None | None | None | CDP FCP |
| dia | 0/1 | None | None | None | CDP FCP |
| safari | 0/2 | None | None | None | visual |

Safari uses visual first-paint (no JS automation permission); others use document FCP. Wall times include each driver's dispatch/polling overhead — compare FCP/visualPaint, not walls alone.
