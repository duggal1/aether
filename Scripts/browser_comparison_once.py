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

from aether_perf_stress import ROOT, SITES, url_steps


BROWSERS = {
    "chrome": {
        "application": "Google Chrome",
        "process": "Google Chrome",
        "bundle": "com.google.Chrome",
        "create": "make new window",
        "tab": "active tab of front window",
        "evaluate": "execute (active tab of front window) javascript (item 1 of argv)",
    },
    "dia": {
        "application": "Dia",
        "process": "Dia",
        "bundle": "company.thebrowser.dia",
        "create": "make new window",
        "tab": "active tab of front window",
        "evaluate": "execute (active tab of front window) javascript (item 1 of argv)",
    },
    "safari": {
        "application": "Safari",
        "process": "Safari",
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
    requestStartMs: navigation ? navigation.requestStart : null,
    responseStartMs: navigation ? navigation.responseStart : null,
    responseEndMs: navigation ? navigation.responseEnd : null,
    redirectCount: navigation ? navigation.redirectCount : null,
    transferSize: navigation ? navigation.transferSize : null,
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
    repeat 50 times
      try
        return id of front window as text
      on error
        delay 0.1
      end try
    end repeat
    error "Benchmark window did not open"
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


def decode_metrics(value):
    """Chromium returns the script's string result already JSON-encoded."""
    data = json.loads(value)
    if isinstance(data, str):
        data = json.loads(data)
    if not isinstance(data, dict):
        raise ValueError(f"unexpected JavaScript result: {value[:120]}")
    return data


def metrics(browser, window_id):
    action = BROWSERS[browser]["evaluate"]
    value = apple(guarded_script(browser, window_id, action), PROBE)
    if not value or value == "missing value":
        raise RuntimeError("No JavaScript result; enable JavaScript from Apple Events in the browser")
    return decode_metrics(value)


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
    wanted = urlsplit(requested)
    found = urlsplit(actual)
    return ((wanted.hostname or "").removeprefix("www.")
            == (found.hostname or "").removeprefix("www.")
            and wanted.path.rstrip("/") == found.path.rstrip("/")
            and wanted.query == found.query)


LAUNCH_FLAGS = {
    "chrome": ("--enable-applescript-javascript",),
    "dia": ("--enable-applescript-javascript",),
    "safari": (),
}
AUTOMATION_PREF = {
    "chrome": ("com.google.Chrome", "AllowJavaScriptAppleEvents"),
    "dia": ("company.thebrowser.dia", "AllowJavaScriptAppleEvents"),
}
EXECUTABLES = {
    "chrome": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "dia": "/Applications/Dia.app/Contents/MacOS/Dia",
    "safari": "/Applications/Safari.app/Contents/MacOS/Safari",
}
PROCESS_NAMES = {
    "chrome": "Google Chrome",
    "dia": "Dia",
    "safari": "Safari",
}
READY_PROBE = "JSON.stringify({automation:true})"


def browser_running(browser):
    if subprocess.run(["pgrep", "-x", PROCESS_NAMES[browser]],
                      capture_output=True, text=True).returncode == 0:
        return True
    return subprocess.run(["pgrep", "-f", EXECUTABLES[browser]],
                          capture_output=True, text=True).returncode == 0


def quit_browser(browser):
    name = BROWSERS[browser]["application"]
    try:
        apple(f'''
on run argv
  tell application "{name}" to quit
end run''')
    except (RuntimeError, subprocess.TimeoutExpired):
        pass
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if not browser_running(browser):
            return
        time.sleep(0.25)
    subprocess.run(["pkill", "-f", EXECUTABLES[browser]], capture_output=True, text=True, timeout=30)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if not browser_running(browser):
            return
        time.sleep(0.25)
    raise RuntimeError(f"{browser} did not quit")


def launch_browser(browser):
    arguments = ["open", "-a", BROWSERS[browser]["application"]]
    flags = LAUNCH_FLAGS[browser]
    if flags:
        arguments.append("--args")
        arguments.extend(flags)
    subprocess.run(arguments, capture_output=True, text=True, timeout=60)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if browser_running(browser):
            time.sleep(1.0)
            return
        time.sleep(0.25)
    raise RuntimeError(f"{browser} did not launch")


def automation_available(browser):
    window_id = create_window(browser)
    try:
        value = apple(guarded_script(browser, window_id, BROWSERS[browser]["evaluate"]), READY_PROBE)
        return bool(value) and value != "missing value"
    except (RuntimeError, subprocess.TimeoutExpired):
        return False
    finally:
        close_window(browser, window_id)


def prepare_browser(browser):
    """Make `execute javascript` available, relaunching with the vendor flag.

    Chromium browsers expose Apple Events JavaScript only through the developer
    toggle or the `--enable-applescript-javascript` launch flag; Safari exposes
    it through Developer > Allow JavaScript from Apple Events. A browser that
    cannot report its own paint timing is a setup failure, never a number.
    """
    if browser_running(browser) and automation_available(browser):
        return
    if browser in AUTOMATION_PREF:
        domain, key = AUTOMATION_PREF[browser]
        subprocess.run(["defaults", "write", domain, key, "-bool", "true"],
                       capture_output=True, text=True, timeout=30)
    if browser_running(browser):
        quit_browser(browser)
    launch_browser(browser)
    if automation_available(browser):
        return
    raise RuntimeError(
        f"{browser}: JavaScript from Apple Events is unavailable; enable it in the browser "
        f"(Chromium: View > Developer > Allow JavaScript from Apple Events, or launch with "
        f"{' '.join(LAUNCH_FLAGS[browser]) or 'Developer > Allow JavaScript from Apple Events'})")



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


def step(browser, window_id, pass_number, index, site, kind, url, timeout, folder, helper):
    name = f"{browser}_pass{pass_number}_{index:02d}_{site}_{kind}"
    started = time.perf_counter()
    started_wall_ms = time.time() * 1000
    row = {"browser": browser, "pass": pass_number, "site": site, "kind": kind, "requestedURL": url,
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
            "requestStartMs": page.get("requestStartMs"),
            "responseStartMs": page.get("responseStartMs"),
            "responseEndMs": page.get("responseEndMs"),
            "redirectCount": page.get("redirectCount"),
            "transferSize": page.get("transferSize"),
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


def save(folder, rows, setup_errors, repeats, paired, site_filter):
    keys = ("dispatchMs", "toReadyMs", "navigationStartDelayMs", "requestStartMs",
            "responseStartMs", "responseEndMs",
            "fcpMs", "lcpMs", "domContentLoadedMs", "loadEventEndMs")
    summary = {
        browser: {"planned": (1 if site_filter else len(SITES)) * 2 * repeats,
                  "attempted": sum(row["browser"] == browser for row in rows),
                  "successful": sum(row["browser"] == browser and row["status"] == "ok" for row in rows),
                  "metrics": {key: distribution([row for row in rows if row["browser"] == browser], key)
                              for key in keys}}
        for browser in BROWSERS
    }
    with open(os.path.join(folder, "results.json"), "w", encoding="utf-8") as output:
        json.dump({"summary": summary, "setupErrors": setup_errors, "steps": rows}, output, indent=2)
    lines = ["# Browser comparison", "",
             f"{repeats} pass(es) of {(1 if site_filter else len(SITES)) * 2} URLs per browser; "
             f"{'each homepage immediately before its route' if paired else 'homepage batch then route batch'}. One benchmark window "
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
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--paired", action="store_true")
    parser.add_argument("--site", choices=tuple(site for site, _, _ in SITES))
    parser.add_argument("--no-screenshots", action="store_true")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.repeats <= 0:
        parser.error("--repeats must be positive")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    folder = os.path.join(ROOT, "perf-results", f"browser_comparison_{stamp}")
    os.makedirs(folder, exist_ok=True)
    rows = []
    setup_errors = {}
    helper = None if args.no_screenshots else build_window_helper(folder)
    selected = BROWSERS if args.browser == "all" else (args.browser,)
    for browser in selected:
        print(f"== {browser}: {args.repeats} pass(es), {'paired' if args.paired else 'homepage batch then route batch'} ==", flush=True)
        window_id = None
        try:
            prepare_browser(browser)
            window_id = create_window(browser)
            for pass_number, index, site, kind, url in url_steps(args.repeats, args.paired, args.site):
                row = step(browser, window_id, pass_number, index, site, kind, url,
                           args.timeout, folder, helper)
                rows.append(row)
                error = row.get("error", "").lower()
                if any(reason in error for reason in
                       ("javascript from apple events", "not authorized", "turned off",
                        "not permitted", "benchmark window changed", "script error",
                        "syntax error", "enable-applescript-javascript")):
                    setup_errors[browser] = row["error"]
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
            save(folder, rows, setup_errors, args.repeats, args.paired, args.site)
    print(f"SAVED: {os.path.relpath(folder, ROOT)}", flush=True)
    if setup_errors:
        raise RuntimeError(f"Browser automation failed: {', '.join(setup_errors)}; see {folder}/results.json")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
