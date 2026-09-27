import Foundation

public enum WebKitTabAudio {
  static let installScript = """
  (() => {
    if (window.__aetherTabAudio) return;
    const nativeMuted = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'muted');
    if (!nativeMuted) return;
    const state = {
      muted: false,
      desiredMuted: new WeakMap(),
      contexts: new Set(),
      suspended: new WeakSet(),
      observer: null
    };
    state.hasActivePlayback = () => {
      const activeMedia = Array.from(document.querySelectorAll('audio,video')).some(element =>
        !element.paused && !element.ended && !element.muted && element.volume > 0);
      if (activeMedia) return true;
      for (const reference of state.contexts) {
        const context = reference.deref();
        if (context?.state === 'running') return true;
        if (!context) state.contexts.delete(reference);
      }
      return false;
    };
    function muteElement(element) {
      if (!(element instanceof HTMLMediaElement)) return;
      if (!state.desiredMuted.has(element)) state.desiredMuted.set(element, nativeMuted.get.call(element));
      nativeMuted.set.call(element, true);
    }
    function muteContext(context) {
      if (state.muted && context.state === 'running') {
        state.suspended.add(context);
        context.suspend().catch(() => {});
      }
    }
    const nativeContext = window.AudioContext || window.webkitAudioContext;
    if (nativeContext) {
      const wrappedContext = new Proxy(nativeContext, {
        construct(target, args, constructor) {
          const context = Reflect.construct(target, args, constructor);
          state.contexts.add(new WeakRef(context));
          muteContext(context);
          return context;
        }
      });
      try {
        Object.defineProperty(window, 'AudioContext', { configurable: true, writable: true, value: wrappedContext });
        if ('webkitAudioContext' in window) {
          Object.defineProperty(window, 'webkitAudioContext', { configurable: true, writable: true, value: wrappedContext });
        }
      } catch (_) {}
    }
    Object.defineProperty(HTMLMediaElement.prototype, 'muted', {
      configurable: true,
      enumerable: nativeMuted.enumerable,
      get() { return nativeMuted.get.call(this); },
      set(value) {
        if (state.muted) {
          state.desiredMuted.set(this, Boolean(value));
          nativeMuted.set.call(this, true);
        } else {
          nativeMuted.set.call(this, value);
        }
      }
    });
    state.setMuted = (muted) => {
      state.muted = Boolean(muted);
      if (state.muted) {
        document.querySelectorAll('audio,video').forEach(muteElement);
        for (const reference of state.contexts) {
          const context = reference.deref();
          if (context) muteContext(context);
          else state.contexts.delete(reference);
        }
        if (!state.observer && document.documentElement) {
          state.observer = new MutationObserver(records => {
            for (const record of records) {
              for (const node of record.addedNodes) {
                if (node instanceof HTMLMediaElement) muteElement(node);
                if (node instanceof Element) node.querySelectorAll('audio,video').forEach(muteElement);
              }
            }
          });
          state.observer.observe(document.documentElement, { childList: true, subtree: true });
        }
        return;
      }
      state.observer?.disconnect();
      state.observer = null;
      document.querySelectorAll('audio,video').forEach(element => {
        if (!state.desiredMuted.has(element)) return;
        nativeMuted.set.call(element, state.desiredMuted.get(element));
        state.desiredMuted.delete(element);
      });
      for (const reference of state.contexts) {
        const context = reference.deref();
        if (context && state.suspended.has(context) && context.state === 'suspended') context.resume().catch(() => {});
        if (!context) state.contexts.delete(reference);
      }
      state.suspended = new WeakSet();
    };
    window.__aetherTabAudio = state;
  })();
  """

  public static func command(muted: Bool) -> String {
    if muted { return installScript + "\nwindow.__aetherTabAudio?.setMuted(true);" }
    return "window.__aetherTabAudio?.setMuted(false);"
  }
}
