import AppKit
import EngineCore
import Foundation

extension WebKitPage {
  func resize(_ size: Size) {
    view.setFrameSize(NSSize(width: size.width, height: size.height))
    publish()
  }

  func captureState() async throws -> CapturePageState {
    let size = try await decode(Size.self, "JSON.stringify({width:document.documentElement.scrollWidth,height:document.documentElement.scrollHeight})")
    return CapturePageState(url: view.url, title: view.title ?? "",
      viewport: Size(width: view.bounds.width, height: view.bounds.height),
      documentSize: size, scroll: try await scrollPosition(), statusCode: statusCode)
  }

  func captureDocument(includeComputedStyles: Bool, redactSensitive: Bool) async throws -> CaptureDocumentData {
    try await decode(CaptureDocumentData.self, """
    (() => {
      const clone = document.documentElement.cloneNode(true);
      const issues = [{code:'webKit-resource-cache',detail:'WebKit does not expose cached response bodies through its public API.'}];
      let redacted = false;
      if (\(redactSensitive)) {
        for (const n of clone.querySelectorAll('input,textarea,[contenteditable=true]')) {
          if (n.hasAttribute('value') || n.textContent) redacted = true;
          n.removeAttribute('value');
          if (n.tagName !== 'INPUT') n.textContent = '';
        }
        for (const n of clone.querySelectorAll('[data-aether-redact]')) {
          if (n.textContent) redacted = true;
          n.textContent = '';
          n.removeAttribute('data-aether-redact');
          n.setAttribute('data-aether-redacted', '');
        }
        if (redacted) issues.push({code:'redaction-applied',detail:'Sensitive content was removed from the capture.'});
      }
      const stylesheets = [];
      if (document.querySelector('canvas')) {
        issues.push({code:'canvas-content',detail:'Canvas pixels are not included in the DOM capture.'});
      }
      if (document.querySelector('iframe')) {
        issues.push({code:'frame-content',detail:'Embedded frame contents are not included in the DOM capture.'});
      }
      for (const sheet of document.styleSheets) {
        try { stylesheets.push({sourceURL:sheet.href,media:sheet.media.mediaText,css:Array.from(sheet.cssRules).map(r=>r.cssText).join('\\n')}); }
        catch { issues.push({code:'cross-origin-stylesheet',detail:sheet.href ?? 'Inaccessible stylesheet'}); }
      }
      // A selector that names one element: ids first, then the nth-of-type
      // path up. Bare tag names repeat across a page and cannot drive an
      // agent back to the element a section or style came from.
      function sel(n, depth) {
        if (!n || !n.tagName) return 'body';
        if (n.id) return '#' + CSS.escape(n.id);
        if (depth > 12 || !n.parentElement) return n.tagName.toLowerCase();
        const tag = n.tagName.toLowerCase();
        const sibs = Array.from(n.parentElement.children).filter(c => c.tagName === n.tagName);
        const self = sibs.length === 1 ? tag : tag + ':nth-of-type(' + (sibs.indexOf(n) + 1) + ')';
        return sel(n.parentElement, depth + 1) + ' > ' + self;
      }
      const props = ['display','position','color','background-color','font-family','font-size',
        'font-weight','line-height','text-align','width','height','padding','margin','border',
        'overflow','flex-direction'];
      const nodes = Array.from(document.querySelectorAll(
        'body,main,header,footer,nav,aside,section,article,figure,h1,h2,h3,img,video,' +
        'form,input,button,select,textarea,a,p,ul,ol')).slice(0,4000).map(n => {
        const r=n.getBoundingClientRect(); const computedStyles={};
        if (\(includeComputedStyles)) {
          try {
            const style=getComputedStyle(n);
            for (const key of props) {
              const v=style.getPropertyValue(key);
              if (v) computedStyles[key]=v;
            }
          } catch {}
        }
        const selector=sel(n,0);
        const scopedSelector=selector.replace(/^html\\s*>\\s*/, '');
        const copy=clone.matches(selector) ? clone : clone.querySelector(scopedSelector) || n;
        let text = null;
        try { text = copy.innerText ? copy.innerText.slice(0,2000) : null; } catch {}
        return {selector,tag:n.tagName.toLowerCase(),role:n.getAttribute('role'),
          text:text,bounds:{origin:{x:r.x+scrollX,y:r.y+scrollY},size:{width:r.width,height:r.height}},
          computedStyles};
      });
      // Every address the page's own pixels come from, so the capture can
      // save the page's images rather than only describing them.
      const resources = [];
      const seen = new Set();
      function push(url, kind) {
        if (resources.length > 2000) return;
        try {
          const abs = new URL(url, document.baseURI).href;
          if (!/^(https?):/i.test(abs) || seen.has(abs)) return;
          seen.add(abs);
          resources.push({url: abs, kind: kind});
        } catch {}
      }
      for (const img of document.querySelectorAll('img')) {
        if (img.currentSrc) push(img.currentSrc, 'image');
        const srcset = img.getAttribute('srcset');
        if (srcset) for (const part of srcset.split(',')) {
          const url = part.trim().split(/\\s+/)[0];
          if (url) push(url, 'image');
        }
      }
      for (const v of document.querySelectorAll('video')) {
        if (v.currentSrc) push(v.currentSrc, 'video');
        if (v.poster) push(v.poster, 'image');
        for (const s of v.querySelectorAll('source[src]')) push(s.src, 'video');
      }
      for (const a of document.querySelectorAll('audio[src], audio source[src]')) {
        if (a.src) push(a.src, 'audio');
      }
      for (const l of document.querySelectorAll('link[rel][href]')) {
        const rel = (l.getAttribute('rel') || '').toLowerCase();
        if (rel.includes('stylesheet')) push(l.href, 'css');
        else if (rel.includes('icon')) push(l.href, 'icon');
      }
      for (const s of document.querySelectorAll('script[src]')) push(s.src, 'script');
      return JSON.stringify({html:'<!doctype html>\\n'+clone.outerHTML,stylesheets,nodes,resources,issues});
    })()
    """)
  }
}
