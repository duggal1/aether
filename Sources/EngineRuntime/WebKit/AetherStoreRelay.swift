import Foundation
import WebKit

// The Chrome Web Store, made to work for this browser.
//
// The store sees a browser that isn't Chrome and says so: a banner asking to
// "Switch to Chrome", and an "Add to Chrome" button that stays grey. Aether
// installs from the store on its own (AetherExtensions.installFromStore,
// through AetherCRX), so on the store's pages the banner goes and the grey
// button is replaced by an "Add to Aether" one — the button people already
// look for, rather than a field somewhere they would have to notice. What gets
// installed is read from the tab's own address, never from anything the page
// says; the page only asks, and the usual confirmation still stands between
// the asking and the installing.

public extension Notification.Name {
  static let aetherStoreInstall = Notification.Name("AetherStoreInstall")
}

enum AetherStoreRelay {
  static let name = "aetherStore"

  /// Main frame, every page, returning at once anywhere but the store. The
  /// store's markup is generated and its class names change between
  /// releases, so nothing here leans on them: the store's own button is the
  /// disabled one that names Chrome, and the banner is the small block
  /// around the one enabled button that does — only that block, since the
  /// store puts the banner and the extension's own header, button and all,
  /// in the same section.
  static let script = """
  (function () {
    if (location.hostname !== 'chromewebstore.google.com' || window.__aetherStore) return;
    var state = { installed: [], busy: null };

    function pageID() {
      var m = location.pathname.match(/\\/detail\\/(?:[^\\/]+\\/)?([a-p]{32})/);
      return m ? m[1] : null;
    }

    function theirs() {
      var buttons = document.querySelectorAll('button[disabled]');
      for (var i = 0; i < buttons.length; i++) {
        var b = buttons[i];
        if (!b.dataset.aether && /chrome/i.test(b.textContent || '')) return b;
      }
      return null;
    }

    // From the banner's own button up, as far as it goes without taking in
    // the header beside it: short, and holding no install button.
    function bannerOf(button) {
      var box = null, up = button.parentElement;
      while (up && up !== document.body) {
        if (up.querySelector('button[disabled], button[data-aether]')) break;
        if ((up.innerText || '').length > 160) break;
        box = up;
        up = up.parentElement;
      }
      return box;
    }

    function hideBanner() {
      // And the floating "Switch to Chrome?" card, known by the Chrome logo
      // it carries in any language — it sits right over the button.
      var cards = document.querySelectorAll('[role="dialog"]');
      for (var c = 0; c < cards.length; c++) {
        if (!cards[c].dataset.aether && cards[c].querySelector('img[src*="productlogos/chrome"]')) {
          cards[c].style.display = 'none';
          cards[c].dataset.aether = 'promo';
        }
      }
      var buttons = document.querySelectorAll('button:not([disabled])');
      for (var i = 0; i < buttons.length; i++) {
        var b = buttons[i];
        if (b.dataset.aether || !/chrome/i.test(b.getAttribute('aria-label') || '')) continue;
        var box = bannerOf(b);
        if (box && !box.dataset.aether) {
          box.style.display = 'none';
          box.dataset.aether = 'banner';
        }
      }
    }

    // The words only, so the button keeps the store's own shape and colour.
    function label(button, text) {
      var walker = document.createTreeWalker(button, NodeFilter.SHOW_TEXT);
      var node, last = null;
      while ((node = walker.nextNode())) { if (node.nodeValue.trim()) last = node; }
      if (last) last.nodeValue = text; else button.textContent = text;
    }

    function render(ours) {
      var id = pageID();
      var installed = !!id && state.installed.indexOf(id) >= 0;
      var busy = !!id && state.busy === id;
      label(ours, installed ? 'Added to Aether' : (busy ? 'Adding…' : 'Add to Aether'));
      ours.disabled = installed || busy;
    }

    function mend() {
      hideBanner();
      if (!pageID()) return;
      var original = theirs();
      if (original && original.parentNode) {
        var ours = original.cloneNode(true);
        ['disabled', 'jsaction', 'jscontroller', 'jsname', 'jslog', 'aria-describedby'].forEach(function (name) {
          ours.removeAttribute(name);
        });
        ours.dataset.aether = 'add';
        original.dataset.aether = 'theirs';
        original.style.display = 'none';
        original.parentNode.insertBefore(ours, original.nextSibling);
        window.webkit.messageHandlers.aetherStore.postMessage({ placed: pageID() });
      }
      renderAll();
    }

    // The store keeps the pages it has left, hidden, beside the one it shows.
    function renderAll() {
      var mine = document.querySelectorAll('button[data-aether="add"]');
      for (var i = 0; i < mine.length; i++) render(mine[i]);
    }

    // Caught on the window, before the store's own handlers — which listen
    // on the document — can see the click at all.
    window.addEventListener('click', function (e) {
      var mine = e.target && e.target.closest && e.target.closest('button[data-aether="add"]');
      if (!mine) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      if (!mine.disabled) window.webkit.messageHandlers.aetherStore.postMessage({ add: true });
    }, true);

    window.__aetherStore = {
      state: function (next) {
        state = next || state;
        renderAll();
      }
    };

    // The store is one page that rewrites itself: whatever it redraws, mend
    // again. A timer rather than a frame — a tab out of sight gets no frames.
    var queued = false;
    new MutationObserver(function () {
      if (queued) return;
      queued = true;
      setTimeout(function () { queued = false; mend(); }, 60);
    }).observe(document.documentElement, { childList: true, subtree: true });
    mend();
  })();
  """
}
