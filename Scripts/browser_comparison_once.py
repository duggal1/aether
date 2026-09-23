#!/usr/bin/env python3
"""Visit the same twenty URLs once each in Chrome, Dia, and Safari."""

import argparse
import datetime
import json
import os
import statistics
import subprocess
import sys
import time
from urllib.parse import urlsplit

from aether_perf_stress import ROOT, SITES


BROWSERS = {
    "chrome": {
        "application": "Google Chrome",
        "bundle": "com.google.Chrome",
        "create": "make new window",
        "tab": "active tab of front window",
        "evaluate": "execute (active tab of front window) javascript (item 1 of argv)",
    },
    "dia": {
        "application": "Dia",
        "bundle": "company.thebrowser.dia",
        "create": "make new window",
        "tab": "active tab of front window",
        "evaluate": "execute (active tab of front window) javascript (item 1 of argv)",
    },
    "safari": {
        "application": "Safari",
        "bundle": "com.apple.Safari",
        "create": "make new document",
        "tab": "current tab of front window",
        "evaluate": "do JavaScript (item 1 of argv) in (current tab of front window)",
    },
}

PROBE = """JSON.stringify((() => {
  const navigation = performance.getEntriesByType('navigation')[0];
  const paints = performance.getEntriesByType('paint');
  const largest = performance.getEntriesByType('largest-contentful-paint');
  const fcp = paints.find(entry => entry.name === 'first-contentful-paint');
  return {
    href: location.href,
    title: document.title,
    readyState: document.readyState,
    timeOrigin: performance.timeOrigin,
    fcpMs: fcp ? fcp.startTime : null,
    lcpMs: largest.length ? largest[largest.length - 1].startTime : null,
    responseStartMs: navigation ? navigation.responseStart : null,
    domContentLoadedMs: navigation ? navigation.domContentLoadedEventEnd : null,
    loadEventEndMs: navigation && navigation.loadEventEnd ? navigation.loadEventEnd : null
  };
})())"""


def apple(script, *arguments):
    result = subprocess.run(["osascript", "-e", script, *arguments],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def create_window(browser):
    config = BROWSERS[browser]
    name = config["application"]
    script = f"""
on run argv
  tell application "{name}"
    activate
    {config["create"]}
    return id of front window as text
  end tell
end run
"""
    return apple(script)


def guarded_script(browser, window_id, action, returns=True):
    name = BROWSERS[browser]["application"]
    statement = f"return {action}" if returns else action
    script = f"""
on run argv
  tell application "{name}"
    if (id of front window as text) is not "{window_id}" then error "Benchmark window changed"
    {statement}
  end tell
end run
"""
    return script


def navigate(browser, window_id, url):
    tab = BROWSERS[browser]["tab"]
    apple(guarded_script(browser, window_id,
                         f"set URL of ({tab}) to item 1 of argv", returns=False), url)


def metrics(browser, window_id):
    action = BROWSERS[browser]["evaluate"]
    value = apple(guarded_script(browser, window_id, action), PROBE)
    if not value or value == "missing value":
        raise RuntimeError("No JavaScript result; enable JavaScript from Apple Events in the browser")
    return json.loads(value)


def close_window(browser, window_id):
    name = BROWSERS[browser]["application"]
    script = f"""
on run argv
  tell application "{name}"
    if (id of front window as text) is (item 1 of argv) then close front window
  end tell
end run
"""
    apple(script, window_id)


def same_site(requested, actual):
    wanted = (urlsplit(requested).hostname or "").removeprefix("www.")
    found = (urlsplit(actual).hostname or "").removeprefix("www.")
    return wanted == found


def wait_fcp(browser, window_id, requested, started_wall_ms, timeout):
    deadline = time.monotonic() + timeout
    last = None
    last_error = None
    while time.monotonic() < deadline:
        try:
            last = metrics(browser, window_id)
            actual = last.get("href") or ""
            origin = last.get("timeOrigin")
            if (same_site(requested, actual)
                    and last.get("fcpMs") is not None
                    and isinstance(origin, (int, float))
                    and origin >= started_wall_ms - 10):
                return last
        except (RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
            last_error = str(error)
            lowered = last_error.lower()
            if ("javascript from apple events" in lowered or "not authorized" in lowered
                    or "turned off" in lowered or "not permitted" in lowered):
                raise RuntimeError(last_error) from error
        time.sleep(0.1)
    raise RuntimeError(f"no current document with FCP within {timeout}s; "
                       f"metrics={json.dumps(last)} error={last_error}")


def build_window_helper(folder):
    executable = os.path.join(folder, "browser-window-id")
    source = os.path.join(ROOT, "Scripts", "browser_window_id.swift")
    result = subprocess.run(["swiftc", source, "-o", executable],
                            capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError(f"window capture helper build failed: {result.stderr.strip()}")
    return executable


def capture(path, helper, browser):
    identity = subprocess.run([helper, BROWSERS[browser]["bundle"]],
                              capture_output=True, text=True, timeout=15)
    if identity.returncode or not identity.stdout.strip().isdigit():
        return "Benchmark browser is not the frontmost visible window"
    result = subprocess.run(["screencapture", "-x", "-l", identity.stdout.strip(), path],
                            capture_output=True, text=True, timeout=30)
    return None if result.returncode == 0 else result.stderr.strip() or "screencapture failed"


def step(browser, window_id, index, site, kind, url, timeout, folder, helper):
    name = f"{browser}_{index:02d}_{site}_{kind}"
    started = time.perf_counter()
    started_wall_ms = time.time() * 1000
    row = {"browser": browser, "site": site, "kind": kind, "requestedURL": url,
           "status": "failed"}
    try:
        navigate(browser, window_id, url)
        row["dispatchMs"] = round((time.perf_counter() - started) * 1000, 1)
        page = wait_fcp(browser, window_id, url, started_wall_ms, timeout)
        row.update({
            "status": "ok", "toReadyMs": round((time.perf_counter() - started) * 1000, 1),
            "finalURL": page["href"], "title": page["title"],
            "redirected": page["href"].rstrip("/") != url.rstrip("/"),
            "navigationStartDelayMs": round(page["timeOrigin"] - started_wall_ms, 1),
            "fcpMs": page["fcpMs"], "lcpMs": page.get("lcpMs"),
            "responseStartMs": page.get("responseStartMs"),
            "domContentLoadedMs": page.get("domContentLoadedMs"),
            "loadEventEndMs": page.get("loadEventEndMs"),
        })
        if helper:
            path = os.path.join(folder, name + ".png")
            error = capture(path, helper, browser)
            if error:
                row["screenshotError"] = error
            else:
                row["screenshot"] = os.path.basename(path)
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        row["error"] = str(error)
        row["elapsedMs"] = round((time.perf_counter() - started) * 1000, 1)
    duration = row.get("toReadyMs", row.get("elapsedMs"))
    print(f"  {name:35s} {row['status']:6s} {duration:8.1f} ms "
          f"{row.get('finalURL', row.get('error', ''))[:85]}", flush=True)
    return row


def distribution(rows, key):
    values = sorted(row[key] for row in rows if row["status"] == "ok"
                    and isinstance(row.get(key), (int, float)))
    if not values:
        return {"count": 0, "medianMs": None, "p95Ms": None, "worstMs": None}
    rank = max(0, (95 * len(values) + 99) // 100 - 1)
    return {"count": len(values), "medianMs": round(statistics.median(values), 1),
            "p95Ms": values[rank], "worstMs": values[-1]}


def save(folder, rows, setup_errors):
    keys = ("dispatchMs", "toReadyMs", "navigationStartDelayMs", "responseStartMs",
            "fcpMs", "lcpMs", "domContentLoadedMs", "loadEventEndMs")
    summary = {
        browser: {"planned": len(SITES) * 2,
                  "attempted": sum(row["browser"] == browser for row in rows),
                  "successful": sum(row["browser"] == browser and row["status"] == "ok" for row in rows),
                  "metrics": {key: distribution([row for row in rows if row["browser"] == browser], key)
                              for key in keys}}
        for browser in BROWSERS
    }
    with open(os.path.join(folder, "results.json"), "w", encoding="utf-8") as output:
        json.dump({"summary": summary, "setupErrors": setup_errors, "steps": rows}, output, indent=2)
    lines = ["# Browser comparison: one visit per URL", "",
             "Twenty URLs per browser, in homepage batch then route batch. One benchmark window "
             "and tab per browser; browsers run sequentially. Timing starts before AppleScript "
             "navigation and ends when the current document reports FCP.", "",
             "| Browser | Completed | Median observed FCP ms | p95 observed FCP ms | Worst ms |",
             "| --- | ---: | ---: | ---: | ---: |"]
    for browser, item in summary.items():
        values = item["metrics"]["toReadyMs"]
        lines.append(f"| {browser} | {item['successful']}/{item['planned']} | "
                     f"{values['medianMs']} | {values['p95Ms']} | {values['worstMs']} |")
    lines += ["", "| Browser | Site | Page | Status | Observed FCP ms | Document FCP ms | Final URL / error |",
              "| --- | --- | --- | --- | ---: | ---: | --- |"]
    for row in rows:
        detail = (row.get("finalURL") or row.get("error") or "").replace("|", "\\|")
        lines.append(f"| {row['browser']} | {row['site']} | {row['kind']} | {row['status']} | "
                     f"{row.get('toReadyMs', '—')} | {row.get('fcpMs', '—')} | {detail} |")
    lines += ["", "Observed FCP includes AppleScript dispatch and polling. Document FCP uses "
              "the page's navigation clock. Screenshots are captured after timing. "
              "Automation overhead differs from Aether's browserctl path; compare page "
              "metrics and images, not the observed wall times alone."]
    with open(os.path.join(folder, "report.md"), "w", encoding="utf-8") as output:
        output.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", choices=(*BROWSERS, "all"), default="all")
    parser.add_argument("--timeout", type=float, default=45)
    parser.add_argument("--no-screenshots", action="store_true")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    folder = os.path.join(ROOT, "perf-results", f"browser_comparison_{stamp}")
    os.makedirs(folder, exist_ok=True)
    rows = []
    setup_errors = {}
    helper = None if args.no_screenshots else build_window_helper(folder)
    selected = BROWSERS if args.browser == "all" else (args.browser,)
    for browser in selected:
        print(f"== {browser}: ten homepages, then ten routes ==", flush=True)
        window_id = None
        try:
            window_id = create_window(browser)
            for kind, position in (("home", 1), ("route", 2)):
                for index, site in enumerate(SITES, 1):
                    name, home, route = site
                    url = home if position == 1 else route
                    row = step(browser, window_id, index, name, kind, url,
                               args.timeout, folder, helper)
                    rows.append(row)
                    error = row.get("error", "").lower()
                    if any(reason in error for reason in
                           ("javascript from apple events", "not authorized", "turned off",
                            "not permitted", "benchmark window changed", "script error",
                            "syntax error")):
                        setup_errors[browser] = row["error"]
                        break
                if browser in setup_errors:
                    break
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
            setup_errors[browser] = str(error)
            print(f"  {browser}: {error}", flush=True)
        finally:
            if window_id is not None:
                try:
                    close_window(browser, window_id)
                except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
                    setup_errors[f"{browser}Cleanup"] = str(error)
            save(folder, rows, setup_errors)
    print(f"SAVED: {os.path.relpath(folder, ROOT)}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
