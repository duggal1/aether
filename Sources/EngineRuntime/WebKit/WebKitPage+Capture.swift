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
      if (\(redactSensitive)) for (const n of clone.querySelectorAll('input,textarea,[contenteditable=true]')) {
        n.removeAttribute('value'); if (n.tagName !== 'INPUT') n.textContent = '';
      }
      const stylesheets = [];
      const issues = [{code:'webKit-resource-cache',detail:'WebKit does not expose cached response bodies through its public API.'}];
      for (const sheet of document.styleSheets) {
        try { stylesheets.push({sourceURL:sheet.href,media:sheet.media.mediaText,css:Array.from(sheet.cssRules).map(r=>r.cssText).join('\\n')}); }
        catch { issues.push({code:'cross-origin-stylesheet',detail:sheet.href ?? 'Inaccessible stylesheet'}); }
      }
      const nodes = Array.from(document.querySelectorAll('body,main,header,footer,nav,section,article,h1,h2,h3,img,video')).slice(0,2000).map(n => {
        const r=n.getBoundingClientRect(); const computedStyles={};
        if (\(includeComputedStyles)) { const style=getComputedStyle(n); for (const key of ['display','color','background-color','font-family','font-size','font-weight','line-height','padding','margin']) computedStyles[key]=style.getPropertyValue(key); }
        return {selector:n.id ? '#'+CSS.escape(n.id) : n.tagName.toLowerCase(),tag:n.tagName.toLowerCase(),role:n.getAttribute('role'),text:n.innerText?.slice(0,2000) ?? null,bounds:{origin:{x:r.x+scrollX,y:r.y+scrollY},size:{width:r.width,height:r.height}},computedStyles};
      });
      return JSON.stringify({html:'<!doctype html>\\n'+clone.outerHTML,stylesheets,nodes,resources:[],issues});
    })()
    """)
  }
}
