JSON.stringify((() => {
  const nav = performance.getEntriesByType('navigation')[0];
  const images = Array.from(document.images);
  const inViewport = n => { const r = n.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.top < innerHeight && r.bottom > 0 && r.left < innerWidth && r.right > 0; };
  const visibleImages = images.filter(inViewport);
  const heading = document.querySelector('h1');
  const headingStyle = heading ? getComputedStyle(heading) : null;
  const body = document.body;
  return {
    url: location.href, title: document.title, readyState: document.readyState,
    visibility: document.visibilityState, timeOrigin: performance.timeOrigin,
    textLength: body?.innerText.length ?? 0, elements: document.querySelectorAll('*').length,
    stylesheets: document.styleSheets.length,
    missingStylesheets: Array.from(document.querySelectorAll('link[rel="stylesheet"]')).filter(n => !n.sheet && !n.disabled).map(n => n.href),
    images: images.length, decodedImages: images.filter(n => n.complete && n.naturalWidth > 0).length,
    brokenImages: images.filter(n => n.complete && n.naturalWidth === 0 && n.currentSrc).map(n => n.currentSrc).slice(0,20),
    visibleImages: visibleImages.length,
    pendingVisibleImages: visibleImages.filter(n => !n.complete).length,
    fonts: document.fonts.status,
    heading: heading?.innerText ?? null,
    headingStyle: headingStyle ? {font:headingStyle.fontFamily,size:headingStyle.fontSize,opacity:headingStyle.opacity,display:headingStyle.display} : null,
    viewport: [innerWidth, innerHeight], documentSize: [document.documentElement.scrollWidth,document.documentElement.scrollHeight],
    userAgent: navigator.userAgent, resources: performance.getEntriesByType('resource').length,
    navigation: nav ? {responseStart:nav.responseStart,responseEnd:nav.responseEnd,domContentLoaded:nav.domContentLoadedEventEnd,load:nav.loadEventEnd,transferSize:nav.transferSize,type:nav.type,responseStatus:nav.responseStatus ?? null} : null,
    paint: performance.getEntriesByType('paint').map(p => ({name:p.name,startTime:p.startTime})),
    challenge: /^(Just a moment|Access denied|Attention Required|403 Forbidden|404 Not Found)/i.test(document.title)
  };
})())
