#!/usr/bin/env python3
"""Headless three-browser comparison. Zero windows, zero focus theft.
Aether via browserd daemon (headless). Chrome/Dia via --headless=new CDP.
Pass 1 = cold process+profile per URL. Pass 2..N = warm, same page navigated.
Usage: python3 Scripts/headless_compare.py [--site X] [--repeats N] [--browsers aether,chrome,dia]"""

import argparse
import datetime
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
import urllib.request
from urllib.parse import urlsplit

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aether_perf_stress import SITES
import websocket

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CTL = os.path.join(ROOT, ".build", "release", "browserctl")
DAEMON = os.path.join(ROOT, ".build", "release", "browserd")
SOCK = "/tmp/aether-headless-bench.sock"

HEADLESS = {
    "chrome": {"app": "Google Chrome", "port": 9340, "prof": "/tmp/hl-chrome"},
    "dia": {"app": "Dia", "port": 9341, "prof": "/tmp/hl-dia"},
}

PROBE = """JSON.stringify((() => {
  const nav = performance.getEntriesByType('navigation')[0];
  const paints = performance.getEntriesByType('paint');
  const l = performance.getEntriesByType('largest-contentful-paint');
  const fcp = paints.find(e => e.name === 'first-contentful-paint');
  return { href: location.href, title: document.title, readyState: document.readyState,
    timeOrigin: performance.timeOrigin, fcpMs: fcp ? fcp.startTime : null,
    loadComplete: document.readyState === 'complete',
    lcpMs: l.length ? l[l.length-1].startTime : null,
    requestStartMs: nav ? nav.requestStart : null, responseStartMs: nav ? nav.responseStart : null,
    responseEndMs: nav ? nav.responseEnd : null, redirectCount: nav ? nav.redirectCount : null,
    transferSize: nav ? nav.transferSize : null,
    domContentLoadedMs: nav ? nav.domContentLoadedEventEnd : null,
    loadEventEndMs: nav && nav.loadEventEnd ? nav.loadEventEnd : null };
})())"""


def run(args, timeout=60):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def same_site(requested, actual):
    w, f = urlsplit(requested), urlsplit(actual)
    return ((w.hostname or "").removeprefix("www.") == (f.hostname or "").removeprefix("www.")
            and w.path.rstrip("/") == f.path.rstrip("/") and w.query == f.query)


def dist(vals):
    vals = sorted(v for v in vals if isinstance(v, (int, float)))
    if not vals:
        return {"count": 0, "medianMs": None, "p95Ms": None, "worstMs": None}
    rank = max(0, (95 * len(vals) + 99) // 100 - 1)
    return {"count": len(vals), "medianMs": round(statistics.median(vals), 1),
            "p95Ms": round(vals[rank], 1), "worstMs": round(vals[-1], 1)}


def ctl(*args, timeout=120):
    r = run([CTL, "--socket", SOCK, *args], timeout=timeout)
    if r.returncode:
        raise RuntimeError(f"browserctl {' '.join(args)}: {(r.stderr.strip() or r.stdout.strip())[:200]}")
    last = None
    for line in r.stdout.strip().splitlines():
        line = line.strip()
        if line.startswith("{"):
            last = json.loads(line)
    if last is None:
        raise RuntimeError(f"browserctl {' '.join(args)}: no JSON in {r.stdout[:200]!r}")
    if last.get("error"):
        raise RuntimeError(str(last["error"])[:300])
    return last["result"]


# ---------------- Aether daemon driver ----------------

class AetherHeadless:
    def __init__(self):
        run(["pkill", "-f", f"browserd --socket {SOCK}"], timeout=15)
        time.sleep(1)
        try:
            os.remove(SOCK)
        except OSError:
            pass
        self.proc = subprocess.Popen([DAEMON, "--socket", SOCK],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                ctl("ping")
                return
            except Exception:
                time.sleep(0.25)
        raise RuntimeError("browserd never came up")

    def close(self):
        try:
            self.proc.terminate()
        except Exception:
            pass

    def cold_step(self, folder, site, kind, url, timeout):
        t0, t0wall = time.perf_counter(), time.time() * 1000
        row = {"browser": "aether", "mode": "cold", "site": site, "kind": kind,
               "requestedURL": url, "status": "failed", "method": "daemon-fcp"}
        try:
            ctx = ctl("context-create", f"cold-{site}-{kind}")["id"]
            pg = ctl("page-open", str(int(ctx)), url, "commit")
            page_id = int(pg["id"])
            row["dispatchMs"] = round((time.perf_counter() - t0) * 1000, 1)
            m, ready_elapsed, load_elapsed = self._probe(page_id, url, t0, t0wall, timeout)
            row.update(self._row(m, ready_elapsed, load_elapsed, t0wall))
            ctl("page-render", str(page_id), os.path.join(folder, f"aether_cold_{site}_{kind}.png"))
            row["screenshot"] = f"aether_cold_{site}_{kind}.png"
            ctl("context-destroy", str(int(ctx)))
        except Exception as e:
            row["error"] = str(e)[:300]
            row["elapsedMs"] = round((time.perf_counter() - t0) * 1000, 1)
        return row

    def warm_setup(self, site, kind, url, timeout):
        ctx = ctl("context-create", f"warm-{site}-{kind}")["id"]
        pg = ctl("page-open", str(int(ctx)), url, "commit")
        return int(ctx), int(pg["id"])

    def warm_step(self, folder, page_id, site, kind, url, timeout):
        t0, t0wall = time.perf_counter(), time.time() * 1000
        row = {"browser": "aether", "mode": "warm", "site": site, "kind": kind,
               "requestedURL": url, "status": "failed", "method": "daemon-fcp"}
        try:
            ctl("page-navigate", str(page_id), url, "commit")
            row["dispatchMs"] = round((time.perf_counter() - t0) * 1000, 1)
            m, ready_elapsed, load_elapsed = self._probe(page_id, url, t0, t0wall, timeout)
            row.update(self._row(m, ready_elapsed, load_elapsed, t0wall))
            ctl("page-render", str(page_id), os.path.join(folder, f"aether_warm_{site}_{kind}.png"))
            row["screenshot"] = f"aether_warm_{site}_{kind}.png"
        except Exception as e:
            row["error"] = str(e)[:300]
            row["elapsedMs"] = round((time.perf_counter() - t0) * 1000, 1)
        return row

    def _probe(self, page_id, url, started, t0wall, timeout):
        deadline = time.monotonic() + timeout
        last, ready_elapsed, load_elapsed = None, None, None
        while time.monotonic() < deadline:
            raw = ctl("page-eval", str(page_id), PROBE)["value"]
            last = json.loads(raw) if isinstance(raw, str) else raw
            if (last.get("fcpMs") is not None and last.get("timeOrigin", 0) >= t0wall - 10
                    and same_site(url, last.get("href", ""))):
                if ready_elapsed is None:
                    ready_elapsed = time.perf_counter() - started
                if last.get("loadComplete") and last.get("loadEventEndMs"):
                    load_elapsed = time.perf_counter() - started
                    break
            time.sleep(0.1)
        if ready_elapsed is None:
            raise RuntimeError(f"no FCP; last={json.dumps(last)[:200]}")
        return last, ready_elapsed, load_elapsed

    @staticmethod
    def _row(m, ready_elapsed, load_elapsed, t0wall):
        return {"status": "ok", "toReadyMs": round(ready_elapsed * 1000, 1),
                "toLoadMs": round(m["timeOrigin"] - t0wall + m["loadEventEndMs"], 1)
                if load_elapsed is not None else None,
                "loadComplete": load_elapsed is not None,
                "finalURL": m["href"], "title": m["title"],
                "navigationStartDelayMs": round(m["timeOrigin"] - t0wall, 1),
                "fcpMs": m["fcpMs"], "lcpMs": m.get("lcpMs"),
                "requestStartMs": m.get("requestStartMs"),
                "responseStartMs": m.get("responseStartMs"),
                "responseEndMs": m.get("responseEndMs"),
                "redirectCount": m.get("redirectCount"),
                "transferSize": m.get("transferSize"),
                "domContentLoadedMs": m.get("domContentLoadedMs"),
                "loadEventEndMs": m.get("loadEventEndMs")}


# ---------------- headless Chromium driver ----------------

class CDP:
    def __init__(self, port):
        tabs = json.load(urllib.request.urlopen(
            f"http://127.0.0.1:{port}/json/list", timeout=10))
        pages = [t for t in tabs if t["type"] == "page"]
        if not pages:
            req = urllib.request.Request(f"http://127.0.0.1:{port}/json/new?about:blank",
                                         method="PUT")
            pages = [json.load(urllib.request.urlopen(req, timeout=10))]
        self.ws = websocket.create_connection(pages[0]["webSocketDebuggerUrl"], timeout=15)
        self.n = 0

    def call(self, method, params=None, timeout=20):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params or {}}))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise RuntimeError(str(msg["error"])[:200])
                return msg.get("result", {})
        raise RuntimeError(f"CDP timeout: {method}")

    def js(self, expr):
        r = self.call("Runtime.evaluate", {"expression": expr, "returnByValue": True})
        v = r["result"]["value"]
        return json.loads(v) if isinstance(v, str) else v

    def shot(self, path):
        import base64 as b64
        with open(path, "wb") as f:
            f.write(b64.b64decode(self.call("Page.captureScreenshot", {"format": "png"})["data"]))

    def close(self):
        try:
            self.ws.close()
        except Exception:
            pass


class HeadlessChromium:
    def __init__(self, tag, cfg):
        self.tag, self.cfg = tag, cfg
        self.proc = None

    def launch_fresh(self):
        self.kill()
        shutil.rmtree(self.cfg["prof"], ignore_errors=True)
        os.makedirs(self.cfg["prof"], exist_ok=True)
        env = dict(os.environ, LSUIElement="1")
        self.proc = subprocess.Popen(
            [f"/Applications/{self.cfg['app']}.app/Contents/MacOS/{self.cfg['app']}",
             "--headless=new", f"--remote-debugging-port={self.cfg['port']}",
             "--remote-allow-origins=*", f"--user-data-dir={self.cfg['prof']}",
             "--no-first-run", "--no-default-browser-check", "--hide-scrollbars",
             "--window-size=1280,800", "--force-device-scale-factor=1",
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{self.cfg['port']}/json/list", timeout=3)
                time.sleep(1.0)
                return
            except Exception:
                time.sleep(0.5)
        raise RuntimeError(f"{self.tag} headless CDP endpoint never came up")

    def kill(self):
        if self.proc:
            try:
                self.proc.terminate()
            except Exception:
                pass
            self.proc = None
        run(["pkill", "-f", self.cfg["prof"]], timeout=15)
        time.sleep(1)

    def step(self, cdp, folder, mode, site, kind, url, timeout):
        t0, t0wall = time.perf_counter(), time.time() * 1000
        row = {"browser": self.tag, "mode": mode, "site": site, "kind": kind,
               "requestedURL": url, "status": "failed", "method": "headless-cdp-fcp"}
        try:
            cdp.call("Page.navigate", {"url": url})
            row["dispatchMs"] = round((time.perf_counter() - t0) * 1000, 1)
            m, ready_elapsed, load_elapsed = None, None, None
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                m = cdp.js(PROBE)
                if (m.get("fcpMs") is not None and m.get("timeOrigin", 0) >= t0wall - 10
                        and same_site(url, m.get("href", ""))):
                    if ready_elapsed is None:
                        ready_elapsed = time.perf_counter()
                    if m.get("loadComplete") and m.get("loadEventEndMs"):
                        load_elapsed = time.perf_counter()
                        break
                time.sleep(0.1)
            if ready_elapsed is None:
                raise RuntimeError(f"no FCP; last={json.dumps(m)[:200]}")
            row.update({"status": "ok", "toReadyMs": round((ready_elapsed - t0) * 1000, 1),
                        "toLoadMs": round(m["timeOrigin"] - t0wall + m["loadEventEndMs"], 1)
                        if load_elapsed else None,
                        "loadComplete": load_elapsed is not None,
                        "finalURL": m["href"], "title": m["title"],
                        "navigationStartDelayMs": round(m["timeOrigin"] - t0wall, 1),
                        "fcpMs": m["fcpMs"], "lcpMs": m.get("lcpMs"),
                        "requestStartMs": m.get("requestStartMs"),
                        "responseStartMs": m.get("responseStartMs"),
                        "responseEndMs": m.get("responseEndMs"),
                        "redirectCount": m.get("redirectCount"),
                        "transferSize": m.get("transferSize"),
                        "domContentLoadedMs": m.get("domContentLoadedMs"),
                        "loadEventEndMs": m.get("loadEventEndMs")})
            cdp.shot(os.path.join(folder, f"{self.tag}_{mode}_{site}_{kind}.png"))
            row["screenshot"] = f"{self.tag}_{mode}_{site}_{kind}.png"
        except Exception as e:
            row["error"] = str(e)[:300]
            row["elapsedMs"] = round((time.perf_counter() - t0) * 1000, 1)
        return row


def print_row(row):
    d = row.get("toReadyMs", row.get("elapsedMs", 0)) or 0
    print(f"  {row['browser']:8s} {row.get('mode',''):5s} {row['site']:14s} {row['kind']:5s} "
          f"{row['status']:6s} {d:8.1f} ms {row.get('finalURL', row.get('error',''))[:60]}",
          flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--site", default=None)
    ap.add_argument("--repeats", type=int, default=1)
    ap.add_argument("--browsers", default="all")
    ap.add_argument("--timeout", type=float, default=45)
    a = ap.parse_args()
    sites = [s for s in SITES if a.site is None or s[0] == a.site]
    if a.site == "example":
        sites = [("example", "https://example.com/", "https://example.com/")]
    if not sites:
        sys.exit(f"unknown site: {a.site}")
    selected = ["aether", "chrome", "dia"] if a.browsers == "all" else a.browsers.split(",")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    folder = os.path.join(ROOT, "perf-results", f"headless_{stamp}")
    os.makedirs(folder, exist_ok=True)
    rows = []

    if "aether" in selected:
        print("== aether (headless daemon) ==", flush=True)
        eng = AetherHeadless()
        try:
            for site, home, route in sites:
                for kind, url in (("home", home), ("route", route)):
                    row = eng.cold_step(folder, site, kind, url, a.timeout)
                    rows.append(row)
                    print_row(row)
            if a.repeats > 1:
                warms = {}
                for site, home, route in sites:
                    for kind, url in (("home", home), ("route", route)):
                        warms[(site, kind)] = (eng.warm_setup(site, kind, url, a.timeout), url)
                for _ in range(a.repeats - 1):
                    for (site, kind), ((ctx, pg), url) in warms.items():
                        row = eng.warm_step(folder, pg, site, kind, url, a.timeout)
                        rows.append(row)
                        print_row(row)
        except Exception as e:
            rows.append({"browser": "aether", "mode": "setup", "site": a.site or "all",
                         "kind": "setup", "requestedURL": "", "status": "failed",
                         "error": f"setup: {e}"[:300]})
            print(f"  aether: SETUP FAILED: {e}", flush=True)
        finally:
            eng.close()

    for tag in [b for b in selected if b in HEADLESS]:
        print(f"== {tag} (headless) ==", flush=True)
        drv = HeadlessChromium(tag, HEADLESS[tag])
        try:
            drv.launch_fresh()
            cdp = CDP(HEADLESS[tag]["port"])
            cdp.call("Page.enable")
            cdp.call("Runtime.enable")
            try:
                for site, home, route in sites:
                    for kind, url in (("home", home), ("route", route)):
                        row = drv.step(cdp, folder, "cold", site, kind, url, a.timeout)
                        rows.append(row)
                        print_row(row)
                for _ in range(a.repeats - 1):
                    for site, home, route in sites:
                        for kind, url in (("home", home), ("route", route)):
                            row = drv.step(cdp, folder, "warm", site, kind, url, a.timeout)
                            rows.append(row)
                            print_row(row)
            finally:
                cdp.close()
        except Exception as e:
            rows.append({"browser": tag, "mode": "setup", "site": a.site or "all",
                         "kind": "setup", "requestedURL": "", "status": "failed",
                         "error": f"setup: {e}"[:300]})
            print(f"  {tag}: SETUP FAILED: {e}", flush=True)
        finally:
            drv.kill()

    summary = {}
    for b in selected:
        mine = [r for r in rows if r.get("browser") == b]
        for mode in ("cold", "warm"):
            ok = [r for r in mine if r.get("mode") == mode and r.get("status") == "ok"]
            summary[f"{b}/{mode}"] = {"completed": f"{len(ok)}/{len([r for r in mine if r.get('mode')==mode])}",
                                      "dispatchMs": dist([r.get("dispatchMs") for r in ok]),
                                      "toReadyMs": dist([r.get("toReadyMs") for r in ok]),
                                      "toLoadMs": dist([r.get("toLoadMs") for r in ok]),
                                      "loadCompleted": sum(r.get("loadComplete") is True for r in ok),
                                      "fcpMs": dist([r.get("fcpMs") for r in ok])}
    with open(os.path.join(folder, "results.json"), "w") as f:
        json.dump({"summary": summary, "steps": rows}, f, indent=2)
    lines = [f"# Headless comparison — {stamp} (zero windows, zero focus theft)", "",
             "| Browser | Completed | Load complete | Median dispatch ms | Median ready ms | Median load ms | Median FCP ms | p95 ready | Worst ready |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for key, v in summary.items():
        lines.append(f"| {key} | {v['completed']} | {v['loadCompleted']} | {v['dispatchMs']['medianMs']} | "
                     f"{v['toReadyMs']['medianMs']} | "
                     f"{v['toLoadMs']['medianMs']} | "
                     f"{v['fcpMs']['medianMs']} | {v['toReadyMs']['p95Ms']} | {v['toReadyMs']['worstMs']} |")
    with open(os.path.join(folder, "report.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"SAVED: {os.path.relpath(folder, ROOT)}", flush=True)
    print("\n".join(lines[2:]), flush=True)
    if any(r["status"] != "ok" for r in rows):
        sys.exit("SOME FAILED — see results.json")


if __name__ == "__main__":
    main()
