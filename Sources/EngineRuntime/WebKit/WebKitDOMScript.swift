import DOM
import EngineCore
import Foundation

struct WebDOMNode: Decodable {
  let index: UInt32
  let generation: UInt32
  let parent: UInt32?
  let children: [UInt32]
  let kind: String
  let tag: String?
  let text: String?
  let attributes: [String: String]
  let role: String
  let name: String
  let value: String?
  let href: String?
  let visible: Bool
  let enabled: Bool
  let editable: Bool
  let bounds: Rect?

  var id: NodeID { NodeID(index: index, generation: generation) }
  var inspected: InspectedNode {
    InspectedNode(id: id, role: role, name: name, value: value, href: href,
      enabled: enabled, editable: editable, visible: visible, bounds: bounds)
  }
  var snapshot: PageNodeSnapshot {
    PageNodeSnapshot(id: id, parent: parent.map { NodeID(index: $0, generation: generation) },
      children: children.map { NodeID(index: $0, generation: generation) }, kind: kind, tag: tag,
      text: text, attributes: attributes, role: role, name: name, visible: visible,
      enabled: enabled, editable: editable, bounds: bounds)
  }
}

enum WebKitDOMScript {
  static func source(generation: UInt32) -> String {
    """
    (() => {
      if (globalThis.__aetherDOM?.generation === \(generation)) return;
      let next = 1;
      const ids = new WeakMap();
      const nodes = new Map();
      const id = n => {
        if (!n) return null;
        if (!ids.has(n)) { ids.set(n, next); nodes.set(next++, new WeakRef(n)); }
        return ids.get(n);
      };
      const describe = n => {
        const el = n.nodeType === 1 ? n : n.parentElement;
        const tag = n.tagName?.toLowerCase() ?? null;
        const style = el ? getComputedStyle(el) : null;
        const rect = el?.getBoundingClientRect();
        const secret = el?.matches('input[type=password],input[autocomplete*=cc-],input[autocomplete=one-time-code]');
        const attrs = {};
        for (const a of n.attributes ?? []) attrs[a.name] = secret && a.name === 'value' ? '[redacted]' : a.value;
        const roles = {a:'link',button:'button',textarea:'textbox',select:'combobox',img:'img',h1:'heading',h2:'heading',h3:'heading'};
        const role = el?.getAttribute('role') ?? (tag === 'input' ? ({checkbox:'checkbox',radio:'radio',submit:'button'}[n.type] ?? 'textbox') : roles[tag]) ?? 'generic';
        const name = n.getAttribute?.('aria-label') || (n.getAttribute?.('aria-labelledby') || '').split(/\\s+/).map(k => document.getElementById(k)?.textContent ?? '').join(' ').trim() || n.getAttribute?.('alt') || Array.from(n.labels ?? []).map(l => l.textContent).join(' ') || (n.innerText ?? n.textContent ?? '').trim().slice(0,2000);
        return {index:id(n),generation:\(generation),parent:id(n.parentNode),children:Array.from(n.childNodes).map(id),
          kind:n.nodeType === 1 ? 'element' : n.nodeType === 3 ? 'text' : 'document',tag,
          text:n.nodeType === 3 ? n.textContent?.slice(0,4000) : null,attributes:attrs,role,name,
          value:secret ? '[redacted]' : (typeof n.value === 'string' ? n.value : null),href:n.href ?? null,
          visible:!!rect && rect.width > 0 && rect.height > 0 && style?.display !== 'none' && style?.visibility !== 'hidden',
          enabled:!el?.matches(':disabled'),editable:!!el?.matches('input,textarea,select,[contenteditable=true]'),
          bounds:rect ? {origin:{x:rect.x+scrollX,y:rect.y+scrollY},size:{width:rect.width,height:rect.height}} : null};
      };
      globalThis.__aetherDOM = {generation:\(generation),describe,get:i => nodes.get(i)?.deref(),snapshot:() => {
        const walker = document.createTreeWalker(document,NodeFilter.SHOW_ELEMENT|NodeFilter.SHOW_TEXT);
        const result = [];
        while (walker.nextNode() && result.length < 20000) {
          if (walker.currentNode.parentElement?.closest('script,style,noscript')) continue;
          result.push(describe(walker.currentNode));
        }
        for (const [key,ref] of nodes) if (!ref.deref()?.isConnected) nodes.delete(key);
        return result;
      }};
    })()
    """
  }
}
