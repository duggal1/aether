import Foundation

@available(macOS 15.4, *)
enum AetherExtensionCompatibility {
    static let application = "aether"
    private static let scriptName = "aether-compat.js"
    private static let marker = "/* Aether extension compatibility shim */"
    private static let ender = "/* End Aether extension compatibility shim */"
    private static let chromeVersion = "140.0.0.0"

    static func prepare(_ folder: URL) throws {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] else {
            throw AetherCRX.Refused.unpack
        }

        let script = compatibilityScript
        try script.write(to: folder.appendingPathComponent(scriptName), atomically: true, encoding: .utf8)
        var permissions = manifest["permissions"] as? [String] ?? []
        if !permissions.contains("nativeMessaging") { permissions.append("nativeMessaging") }
        manifest["permissions"] = permissions

        if var background = manifest["background"] as? [String: Any] {
            if let worker = background["service_worker"] as? String,
               let workerURL = packageURL(worker, folder: folder),
               var source = try? String(contentsOf: workerURL, encoding: .utf8) {
                let current = "\(marker)\n\(script)\n\(ender)\n"
                if !source.hasPrefix(current) {
                    if source.hasPrefix(marker) {
                        if let end = source.range(of: ender) {
                            source = String(source[end.upperBound...]).trimmingCharacters(in: .newlines)
                        } else if let end = source.range(of: "\n})();\n") {
                            source = String(source[end.upperBound...])
                        }
                    }
                    source = current + source
                    try source.write(to: workerURL, atomically: true, encoding: .utf8)
                }
            }
            if var scripts = background["scripts"] as? [String] {
                if !scripts.contains(scriptName) { scripts.insert(scriptName, at: 0) }
                background["scripts"] = scripts
            }
            manifest["background"] = background
        }

        if let entries = manifest["content_scripts"] as? [[String: Any]] {
            manifest["content_scripts"] = entries.map { entry in
                var result = entry
                var scripts = result["js"] as? [String] ?? []
                if !scripts.contains(scriptName) { scripts.insert(scriptName, at: 0) }
                result["js"] = scripts
                return result
            }
        }

        let manifestData = try JSONSerialization.data(withJSONObject: manifest,
                                                       options: [.prettyPrinted, .withoutEscapingSlashes])
        try manifestData.write(to: manifestURL, options: .atomic)

        let files = FileManager.default
        let walker = files.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  ["html", "htm"].contains(url.pathExtension.lowercased()),
                  var html = try? String(contentsOf: url, encoding: .utf8),
                  !html.contains(scriptName) else { continue }
            let tag = "<script src=\"/\(scriptName)\"></script>"
            if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
                html.insert(contentsOf: tag, at: head.upperBound)
            } else {
                html = tag + html
            }
            try html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// A path a package names, resolved and kept inside the folder it came
    /// in: `..` is not a way out of the package, and neither is a link.
    static func fileInside(_ name: String, of folder: URL) -> URL? {
        packageURL(name, folder: folder)
    }

    private static func packageURL(_ name: String, folder: URL) -> URL? {
        let root = folder.standardizedFileURL
        let file = root.appendingPathComponent(name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"),
              (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { return nil }
        return file
    }

    private static let compatibilityScript = #"""
    (() => {
      const root = globalThis;
      const chrome = root.chrome || root.browser;
      if (!chrome || !chrome.runtime || !chrome.runtime.id || root.__aetherCompatibility) return;
      Object.defineProperty(root, "__aetherCompatibility", { value: true });

      const nativeIdle = typeof root.requestIdleCallback === "function" ? root.requestIdleCallback.bind(root) : null;
      const nativeCancel = typeof root.cancelIdleCallback === "function" ? root.cancelIdleCallback.bind(root) : null;
      if (!nativeIdle || !nativeCancel) {
        const pending = new Map();
        let nextID = 0;
        root.requestIdleCallback = (callback, options = {}) => {
          const id = ++nextID;
          const timer = setTimeout(() => {
            pending.delete(id);
            const started = Date.now();
            callback({ didTimeout: false, timeRemaining: () => Math.max(0, 50 - (Date.now() - started)) });
          }, options.timeout === undefined ? 1 : Math.min(50, options.timeout));
          pending.set(id, timer);
          return id;
        };
        root.cancelIdleCallback = id => {
          const timer = pending.get(id);
          if (timer !== undefined) clearTimeout(timer);
          pending.delete(id);
        };
      }

      for (const key of ["browser", "chrome"]) {
        const descriptor = Object.getOwnPropertyDescriptor(root, key);
        if (!descriptor || !descriptor.configurable) continue;
        let value = root[key];
        const carriesRuntime = next => { try { return !!(next && next.runtime && next.runtime.id); } catch (_) { return false; } };
        try {
          Object.defineProperty(root, key, {
            configurable: false,
            enumerable: descriptor.enumerable,
            get: () => value,
            set: next => { if (carriesRuntime(next)) value = next; }
          });
        } catch (_) {}
      }

      const extensionPage = /^(chrome|webkit)-extension:$/.test(location.protocol);
      const worker = typeof ServiceWorkerGlobalScope !== "undefined" && root instanceof ServiceWorkerGlobalScope;
      const runtime = chrome.runtime;
      const native = (api, args) =>
        runtime.sendNativeMessage("aether", { api, args: JSON.parse(JSON.stringify(args ?? [])) });
      const embedded = extensionPage && typeof window !== "undefined" && window.top !== window && (() => {
        try { return window.top.location.origin !== location.origin; } catch (_) { return true; }
      })();

      if (extensionPage && typeof navigator !== "undefined" && !/ Chrome\//.test(navigator.userAgent)) {
        const chromeUA = navigator.userAgent.replace(/ Version\/[\d.]+.*$/, "").replace(/ Safari\/[\d.]+$/, "") + " Chrome/__AETHER_CHROME__ Safari/537.36";
        try {
          const proto = worker && typeof WorkerNavigator !== "undefined" ? WorkerNavigator.prototype : Navigator.prototype;
          Object.defineProperty(proto, "userAgent", { get: () => chromeUA, configurable: true });
          Object.defineProperty(proto, "appVersion", { get: () => chromeUA.replace(/^Mozilla\//, ""), configurable: true });
          Object.defineProperty(proto, "vendor", { get: () => "Google Inc.", configurable: true });
        } catch (_) {}
      }

      // The popup an extension sets for its button, told to the browser too:
      // Aether opens a popup itself, and has to know which page it is now.
      for (const name of ["action", "browserAction"]) {
        const api = chrome[name];
        if (!api || typeof api.setPopup !== "function") continue;
        const setPopup = api.setPopup.bind(api);
        try {
          Object.defineProperty(api, "setPopup", { configurable: true, value: (details = {}, callback) => {
            const tell = index => native("action.popup", [details.popup || "", index]).catch(() => {});
            if (typeof details.tabId === "number" && chrome.tabs && typeof chrome.tabs.get === "function") chrome.tabs.get(details.tabId).then(t => tell(t.index), () => {});
            else tell(-1);
            return setPopup(details, callback);
          }});
        } catch (_) {}
      }

      // WebKit says "install" again when an extension is taken up afresh in
      // the same session — another profile's context, a Reload, a worker
      // brought back — where Chrome says "update"; extensions open their
      // welcome page on "install". The first load of a session is reported
      // as-is, and every later one as the update it is, so one install opens
      // one tab instead of one per context.
      if (worker && runtime.onInstalled && typeof runtime.onInstalled.addListener === "function") {
        let decided = null;
        const seenBefore = () => decided || (decided = Promise.resolve()
          .then(() => native("background.loadedBefore", []))
          .then(v => !!v, () => false));
        const add = runtime.onInstalled.addListener.bind(runtime.onInstalled);
        const remove = runtime.onInstalled.removeListener.bind(runtime.onInstalled);
        const wrapped = new Map();
        const putEvent = (target, key, value) => { try { Object.defineProperty(target, key, { configurable: true, value }); } catch (_) {} };
        putEvent(runtime.onInstalled, "addListener", listener => {
          const w = details => {
            if (!details || details.reason !== "install") return listener(details);
            seenBefore().then(seen => listener(seen ? { ...details, reason: "update", previousVersion: runtime.getManifest().version } : details));
          };
          wrapped.set(listener, w);
          return add(w);
        });
        putEvent(runtime.onInstalled, "removeListener", listener => {
          const w = wrapped.get(listener);
          wrapped.delete(listener);
          return remove(w || listener);
        });
        putEvent(runtime.onInstalled, "hasListener", listener => wrapped.has(listener));
      }

      if (worker) {
        try {
          runtime.onMessage.addListener((message, sender, sendResponse) => {
            if (message && message.__aetherCall && sender.id === runtime.id) {
              const { namespace, method, args } = message.__aetherCall;
              if (namespace === "tabs" && method === "getCurrent") {
                sendResponse({ value: sender.tab || null });
                return false;
              }
              const api = chrome[namespace];
              const operation = api && api[method];
              if (typeof operation !== "function" || method.startsWith("on")) {
                sendResponse({ error: "Unsupported extension API call" });
                return false;
              }
              Promise.resolve().then(() => operation.apply(api, args || [])).then(
                value => sendResponse({ value }),
                error => sendResponse({ error: String(error && error.message || error) })
              );
              return true;
            }
            return false;
          });
        } catch (_) {}
      }

      if (worker && chrome.tabs && typeof chrome.tabs.sendMessage === "function") {
        const sendTabMessage = chrome.tabs.sendMessage.bind(chrome.tabs);
        const sendRuntimeMessage = Object.getPrototypeOf(runtime).sendMessage;
        const alsoFramed = (contentAnswer, tabId, message, options) => {
          const navigation = chrome.webNavigation;
          if (!navigation || typeof navigation.getAllFrames !== "function" || typeof tabId !== "number") return contentAnswer;
          const extensionURL = runtime.getURL("");
          const frameId = options && typeof options.frameId === "number" ? options.frameId : null;
          const framedAnswer = Promise.resolve(navigation.getAllFrames({ tabId })).then(frames => {
            const urls = (frames || []).filter(frame => frame.url && frame.url.startsWith(extensionURL) &&
              frame.frameId !== 0 && (frameId === null || frame.frameId === frameId)).map(frame => frame.url);
            if (!urls.length) return undefined;
            return sendRuntimeMessage.call(runtime, { __aetherToFrame: { tabId, urls, message } });
          }, () => undefined);
          return new Promise((resolve, reject) => {
            let pending = 2;
            let failure;
            const none = () => { if (--pending === 0) failure ? reject(failure) : resolve(undefined); };
            contentAnswer.then(value => value !== undefined ? resolve(value) : none(), error => { failure = error; none(); });
            framedAnswer.then(value => value !== undefined ? resolve(value) : none(), () => none());
          });
        };
        Object.defineProperty(chrome.tabs, "sendMessage", { configurable: true, writable: true, value: (...input) => {
          const callback = typeof input[input.length - 1] === "function" ? input.pop() : null;
          const tabId = input[0], message = input[1], options = input[2];
          let answer;
          try { answer = Promise.resolve(sendTabMessage(...input)); }
          catch (error) { answer = Promise.reject(error); }
          answer = alsoFramed(answer, tabId, message, options);
          if (!callback) return answer;
          answer.then(callback, error => {
            try { Object.defineProperty(runtime, "lastError", { configurable: true, value: { message: String(error) } }); } catch (_) {}
            try { callback(undefined); } finally { try { delete runtime.lastError; } catch (_) {} }
          });
          return undefined;
        }});
      }

      if (embedded) {
        if (runtime.onMessage && typeof runtime.onMessage.addListener === "function") {
          const event = runtime.onMessage;
          const add = event.addListener.bind(event);
          const remove = event.removeListener.bind(event);
          const wrappers = new WeakMap();
          try {
            Object.defineProperty(event, "addListener", { configurable: true, value: listener => {
              const wrapper = (message, sender, sendResponse) => {
                if (!message || !message.__aetherToFrame) return listener(message, sender, sendResponse);
                const target = message.__aetherToFrame;
                if (!embedded || !(target.urls || []).includes(location.href)) return false;
                Promise.resolve(chrome.tabs && chrome.tabs.getCurrent ? chrome.tabs.getCurrent() : null).then(tab => {
                  if (!tab || tab.id !== target.tabId) {
                    setTimeout(() => sendResponse(undefined), 10000);
                    return;
                  }
                  let result;
                  try { result = listener(target.message, sender, sendResponse); }
                  catch (error) { sendResponse({ __aetherError: String(error) }); return; }
                  if (result && typeof result.then === "function") result.then(sendResponse, error => sendResponse({ __aetherError: String(error) }));
                  else if (result !== true) sendResponse(undefined);
                }, () => setTimeout(() => sendResponse(undefined), 10000));
                return true;
              };
              wrappers.set(listener, wrapper);
              return add(wrapper);
            }});
            Object.defineProperty(event, "removeListener", { configurable: true, value: listener => {
              const wrapper = wrappers.get(listener);
              wrappers.delete(listener);
              return remove(wrapper || listener);
            }});
          } catch (_) {}
        }
        const direct = new Set(["runtime", "storage", "i18n", "extension", "permissions", "dom"]);
        const reportError = (message, error) => {
          try { Object.defineProperty(runtime, "lastError", { configurable: true, value: { message: String(error) } }); } catch (_) {}
          try { message(); } finally { try { delete runtime.lastError; } catch (_) {} }
        };
        for (const namespace of Object.keys(chrome)) {
          if (direct.has(namespace)) continue;
          let api;
          try { api = chrome[namespace]; } catch (_) { continue; }
          if (!api || typeof api !== "object") continue;
          const names = new Set();
          for (let proto = api; proto && proto !== Object.prototype; proto = Object.getPrototypeOf(proto)) {
            for (const name of Object.getOwnPropertyNames(proto)) names.add(name);
          }
          for (const method of names) {
            if (method === "constructor" || method === "connect" || method.startsWith("on")) continue;
            let original;
            try { original = api[method]; } catch (_) { continue; }
            if (typeof original !== "function") continue;
            try {
              Object.defineProperty(api, method, { configurable: true, writable: true, value: (...input) => {
                const callback = typeof input[input.length - 1] === "function" ? input.pop() : null;
                const args = input.filter((value, index) => !(value === undefined && index >= input.length - 1));
                let payload;
                try { payload = JSON.parse(JSON.stringify(args)); }
                catch (error) { return callback ? reportError(() => callback(undefined), error) : Promise.reject(error); }
                const reply = runtime.sendMessage({ __aetherCall: { namespace, method, args: payload } }).then(result => {
                  if (!result) throw new Error("No response from the extension worker");
                  if (result.error) throw new Error(result.error);
                  return result.value;
                });
                if (!callback) return reply;
                reply.then(callback, error => reportError(() => callback(undefined), error));
                return undefined;
              }});
            } catch (_) {}
          }
        }
      }

      if (!embedded && !worker && runtime.onMessage && typeof runtime.onMessage.addListener === "function") {
        const event = runtime.onMessage;
        const add = event.addListener.bind(event);
        const remove = event.removeListener.bind(event);
        const wrappers = new WeakMap();
        try {
          Object.defineProperty(event, "addListener", { configurable: true, value: listener => {
            const wrapper = (message, sender, sendResponse) =>
              message && message.__aetherToFrame ? false : listener(message, sender, sendResponse);
            wrappers.set(listener, wrapper);
            return add(wrapper);
          }});
          Object.defineProperty(event, "removeListener", { configurable: true, value: listener => {
            const wrapper = wrappers.get(listener);
            wrappers.delete(listener);
            return remove(wrapper || listener);
          }});
        } catch (_) {}
      }

      if (worker && typeof root.WebSocket === "function" && typeof runtime.connectNative === "function") {
        const connectNative = runtime.connectNative.bind(runtime);
        const encode = bytes => {
          let text = "";
          for (let index = 0; index < bytes.length; index += 0x8000) text += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
          return btoa(text);
        };
        const decode = text => {
          const binary = atob(text), bytes = new Uint8Array(binary.length);
          for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
          return bytes.buffer;
        };
        class AetherWebSocket extends EventTarget {
          #port; #state = 0; #queue = Promise.resolve(); #origin; #hello;
          constructor(address, protocols) {
            super();
            let url;
            try { url = new URL(address, location.href); } catch (_) { throw new DOMException("Invalid WebSocket URL", "SyntaxError"); }
            if (url.protocol === "http:") url.protocol = "ws:";
            if (url.protocol === "https:") url.protocol = "wss:";
            if (!/^wss?:$/.test(url.protocol) || url.hash) throw new DOMException("Invalid WebSocket URL", "SyntaxError");
            const list = protocols === undefined ? [] : (Array.isArray(protocols) ? protocols : [protocols]).map(String);
            Object.defineProperty(this, "url", { value: url.href, enumerable: true });
            this.#origin = url.origin;
            this.protocol = ""; this.extensions = ""; this.binaryType = "blob"; this.bufferedAmount = 0;
            this.onopen = null; this.onmessage = null; this.onerror = null; this.onclose = null;
            this.#hello = { open: this.url, protocols: list, userAgent: navigator.userAgent };
            this.#connect();
          }
          #connect() {
            const port = connectNative("aether.socket");
            let ready = false, tries = 0;
            this.#port = port;
            const retry = () => {
              if (ready || this.#state === 3) return;
              if (tries++ >= 20) { this.#fire("error"); this.#closed(1006, "", false); return; }
              try { port.postMessage(this.#hello); } catch (_) {}
              setTimeout(retry, 100 * Math.min(tries, 5));
            };
            port.onMessage.addListener(message => {
              ready = true;
              if (message && message.ready) return;
              this.#take(message);
            });
            port.onDisconnect.addListener(() => {
              if (this.#state !== 3) { this.#fire("error"); this.#closed(1006, "", false); }
            });
            retry();
          }
          get readyState() { return this.#state; }
          #fire(type, init) {
            let event;
            if (type === "message") event = new MessageEvent(type, init);
            else if (type === "close" && typeof CloseEvent === "function") event = new CloseEvent(type, init);
            else { event = new Event(type); if (init) for (const key in init) Object.defineProperty(event, key, { value: init[key] }); }
            const handler = this["on" + type];
            if (typeof handler === "function") { try { handler.call(this, event); } catch (error) { setTimeout(() => { throw error; }); } }
            this.dispatchEvent(event);
          }
          #closed(code, reason, clean) {
            this.#state = 3;
            try { this.#port.disconnect(); } catch (_) {}
            this.#fire("close", { code, reason, wasClean: clean });
          }
          #take(message) {
            if (!message || this.#state === 3) return;
            if ("opened" in message) { this.protocol = message.opened; this.#state = 1; this.#fire("open"); }
            else if ("text" in message) this.#fire("message", { data: message.text, origin: this.#origin });
            else if ("binary" in message) {
              const bytes = decode(message.binary);
              this.#fire("message", { data: this.binaryType === "arraybuffer" ? bytes : new Blob([bytes]), origin: this.#origin });
            } else if (message.failed) this.#fire("error");
            else if ("closed" in message) this.#closed(message.closed, message.reason || "", !!message.clean);
          }
          send(data) {
            if (this.#state === 0) throw new DOMException("WebSocket is still connecting", "InvalidStateError");
            if (this.#state !== 1) return;
            const post = message => { try { this.#port.postMessage(message); } catch (_) {} };
            if (typeof data === "string") { this.#queue = this.#queue.then(() => post({ send: data })); return; }
            const bytes = data instanceof ArrayBuffer ? Promise.resolve(new Uint8Array(data))
              : ArrayBuffer.isView(data) ? Promise.resolve(new Uint8Array(data.buffer, data.byteOffset, data.byteLength))
              : data instanceof Blob ? data.arrayBuffer().then(buffer => new Uint8Array(buffer)) : Promise.resolve(null);
            this.#queue = this.#queue.then(() => bytes).then(value => value ? post({ sendBinary: encode(value) }) : post({ send: String(data) }));
          }
          close(code = 1000, reason = "") {
            if (code !== 1000 && !(code >= 3000 && code <= 4999)) throw new DOMException("Invalid WebSocket close code", "InvalidAccessError");
            if (this.#state >= 2) return;
            this.#state = 2;
            this.#queue = this.#queue.then(() => { try { this.#port.postMessage({ close: code, reason: String(reason) }); } catch (_) {} });
          }
        }
        for (const [key, value] of Object.entries({ CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 })) {
          Object.defineProperty(AetherWebSocket, key, { value });
          Object.defineProperty(AetherWebSocket.prototype, key, { value });
        }
        Object.defineProperty(root, "WebSocket", { value: AetherWebSocket, configurable: true, writable: true });
      }
    })();
    """#.replacingOccurrences(of: "__AETHER_CHROME__", with: chromeVersion)
}
