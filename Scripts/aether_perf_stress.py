#!/usr/bin/env python3
"""Visit the twenty supplied URLs once in the real Aether.app."""

import argparse
import datetime
import hashlib
import json
import os
import statistics
import subprocess
import sys
import time
from urllib.parse import urlsplit

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, ".build", "Aether.app")
BIN = os.path.join(APP, "Contents", "MacOS", "AetherApp")
CTL = os.path.join(ROOT, ".build", "release", "browserctl")
SITES = (
    ("clay", "https://www.clay.com/", "https://www.clay.com/pricing"),
    ("apollo", "https://www.apollo.io/", "https://www.apollo.io/pricing"),
    ("awwwards", "https://www.awwwards.com/", "https://www.awwwards.com/websites/art/"),
    ("land-book", "https://land-book.com/", "https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies"),
    ("calendly", "https://calendly.com/", "https://calendly.com/pricing"),
    ("wisprflow", "https://wisprflow.ai/", "https://wisprflow.ai/pricing"),
    ("jack-and-jill", "https://www.jackandjill.ai/", "https://www.jackandjill.ai/pricing"),
    ("privy", "https://www.privy.io/", "https://www.privy.io/careers-old"),
    ("airtable", "https://www.airtable.com/", "https://www.airtable.com/solutions/enterprise"),
    ("intercom", "https://www.intercom.com/", "https://www.intercom.com/customers"),
)


def url_steps(repeats=1, paired=False, site_filter=None):
    sites = tuple(site for site in SITES if site_filter is None or site[0] == site_filter)
    for pass_number in range(1, repeats + 1):
        if paired:
            for index, (site, home, route) in enumerate(sites, 1):
                yield pass_number, index, site, "home", home
                yield pass_number, index, site, "route", route
        else:
            for kind in ("home", "route"):
                for index, (site, home, route) in enumerate(sites, 1):
                    yield pass_number, index, site, kind, home if kind == "home" else route


def command(args, timeout=120):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def app(*args):
    result = command([CTL, "--app", *args], timeout=15)
    if result.returncode:
        raise RuntimeError(f"browserctl {' '.join(args)}: {result.stderr.strip()}")
    response = json.loads(result.stdout)
    if response.get("error"):
        raise RuntimeError(str(response["error"]))
    return response["result"]


def check_build():
    if not os.path.isfile(BIN):
        raise RuntimeError(f"Missing packaged app: {APP}. Finish the current app build before benchmarking.")
    if not os.path.isfile(CTL):
        raise RuntimeError(f"Missing browserctl: {CTL}. Finish the current app build before benchmarking.")
    sources = []
    for path, directories, files in os.walk(os.path.join(ROOT, "Sources")):
        directories[:] = [name for name in directories
                          if name not in ("Tests", "Examples", ".build")]
        sources.extend(os.path.getmtime(os.path.join(path, name))
                       for name in files if name.endswith(".swift"))
    latest = max(sources)
    if latest > os.path.getmtime(BIN):
        raise RuntimeError("Aether.app is older than Swift sources. Finish packaging a current build before benchmarking.")


def sha256():
    digest = hashlib.sha256()
    with open(BIN, "rb") as binary:
        for chunk in iter(lambda: binary.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def quit_app():
    command(["pkill", "-x", "AetherApp"])
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if command(["pgrep", "-x", "AetherApp"]).returncode:
            return
        time.sleep(0.1)
    raise RuntimeError("AetherApp did not quit")


def launch():
    quit_app()
    started = time.perf_counter()
    result = command(["open", APP], timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            status = app("app-status")
            if status["ready"] and status["nativeWindows"]:
                return round((time.perf_counter() - started) * 1000, 1)
        except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired):
            pass
        time.sleep(0.1)
    raise RuntimeError("Aether.app did not expose a ready native window")


def tab_state(tab_id):
    for tab in app("app-tabs"):
        if tab["id"] == tab_id:
            return tab
    raise RuntimeError(f"tab {tab_id} disappeared")


def same_site(requested, actual):
    wanted = urlsplit(requested)
    found = urlsplit(actual)
    return (wanted.hostname or "").removeprefix("www.") == (found.hostname or "").removeprefix("www.") \
        and wanted.path.rstrip("/") == found.path.rstrip("/") and wanted.query == found.query


def wait_paint(tab_id, requested, started_wall_ms, timeout):
    deadline = time.monotonic() + timeout
    last_tab = None
    last_metrics = None
    while time.monotonic() < deadline:
        last_tab = tab_state(tab_id)
        if last_tab["state"] == "failed":
            raise RuntimeError(f"page failed: {last_tab.get('error')}")
        if last_tab["state"] == "ready" and last_tab["contentReady"] and not last_tab.get("pendingURL"):
            last_metrics = app("app-metrics", tab_id)
            actual = last_metrics.get("href") or ""
            origin = last_metrics.get("timeOrigin")
            if same_site(requested, actual) and last_metrics.get("fcpMs") is not None:
                if isinstance(origin, (int, float)) and origin >= started_wall_ms - 10:
                    return last_tab, last_metrics, "document"
        time.sleep(0.05)
    raise RuntimeError(
        f"no current document with FCP within {timeout}s; "
        f"tab={json.dumps(last_tab)} metrics={json.dumps(last_metrics)}")


def capture_window(path):
    status = app("app-status")
    windows = [window for window in status["nativeWindows"] if window["visible"]]
    if not windows:
        return "No visible Aether window"
    result = command(["screencapture", "-x", "-l", str(windows[0]["number"]), path], timeout=30)
    return None if result.returncode == 0 else result.stderr.strip() or "screencapture failed"


def step(pass_number, index, site, kind, requested, action, tab_id, timeout, folder, screenshots):
    label = f"pass{pass_number}_{index:02d}_{site}_{kind}"
    started = time.perf_counter()
    started_wall_ms = time.time() * 1000
    row = {"step": label, "pass": pass_number, "site": site, "kind": kind,
           "requestedURL": requested, "status": "failed"}
    try:
        response = action()
        if tab_id is None:
            tab_id = response["id"]
        row["tabID"] = tab_id
        row["dispatchMs"] = round((time.perf_counter() - started) * 1000, 1)
        tab, metrics, navigation_kind = wait_paint(tab_id, requested, started_wall_ms, timeout)
        row.update({
            "status": "ok",
            "navigationKind": navigation_kind,
            "toReadyMs": round((time.perf_counter() - started) * 1000, 1),
            "finalURL": metrics["href"],
            "redirected": metrics["href"].rstrip("/") != requested.rstrip("/"),
            "title": tab["title"],
            "fcpMs": metrics.get("fcpMs"),
            "lcpMs": metrics.get("lcpMs"),
            "requestStartMs": metrics.get("requestStartMs"),
            "responseStartMs": metrics.get("responseStartMs"),
            "responseEndMs": metrics.get("responseEndMs"),
            "redirectCount": metrics.get("redirectCount"),
            "transferSize": metrics.get("transferSize"),
            "domContentLoadedMs": metrics.get("domContentLoadedMs"),
            "loadEventEndMs": metrics.get("loadEventEndMs"),
            "navigationStartDelayMs": round(metrics["timeOrigin"] - started_wall_ms, 1)
            if navigation_kind == "document" else None,
            "uiProgress": tab["progress"],
        })
        if screenshots:
            path = os.path.join(folder, label + ".png")
            error = capture_window(path)
            if error:
                row["screenshotError"] = error
            else:
                row["screenshot"] = os.path.basename(path)
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        row["error"] = str(error)
        row["elapsedMs"] = round((time.perf_counter() - started) * 1000, 1)
    duration = row.get("toReadyMs", row.get("elapsedMs"))
    print(f"  {label:36s} {row['status']:6s} {duration:8.1f} ms "
          f"{row.get('finalURL', row.get('error', ''))[:90]}", flush=True)
    return row, tab_id


def distribution(rows, key):
    values = sorted(row[key] for row in rows if row["status"] == "ok"
                    and isinstance(row.get(key), (int, float)))
    if not values:
        return {"count": 0, "medianMs": None, "p95Ms": None, "worstMs": None}
    rank = max(0, (95 * len(values) + 99) // 100 - 1)
    return {"count": len(values), "medianMs": round(statistics.median(values), 1),
            "p95Ms": values[rank], "worstMs": values[-1]}


def statistics_for(rows):
    ready = distribution(rows, "toReadyMs")
    documents = [row for row in rows if row.get("navigationKind") == "document"]
    ready["metrics"] = {
        key: distribution(documents if key in ("fcpMs", "lcpMs", "requestStartMs", "responseStartMs",
                                                "responseEndMs",
                                                "domContentLoadedMs", "loadEventEndMs",
                                                "navigationStartDelayMs") else rows, key)
        for key in ("dispatchMs", "toReadyMs", "navigationStartDelayMs",
                    "requestStartMs", "responseStartMs", "responseEndMs", "fcpMs", "lcpMs",
                    "domContentLoadedMs", "loadEventEndMs")
    }
    return ready


def save(folder, stamp, digest, launch_ms, rows):
    completed = sum(row["status"] == "ok" for row in rows)
    summary = {
        "binarySHA256": digest, "appLaunchMs": launch_ms,
        "attempted": len(rows), "successful": completed, "failed": len(rows) - completed,
        "all": statistics_for(rows),
        "byPass": {str(number): statistics_for([row for row in rows if row["pass"] == number])
                   for number in sorted({row["pass"] for row in rows})},
        "bySite": {site: statistics_for([row for row in rows if row["site"] == site])
                   for site, _, _ in SITES},
    }
    with open(os.path.join(folder, "results.json"), "w", encoding="utf-8") as output:
        json.dump({"summary": summary, "steps": rows}, output, indent=2)
    lines = [f"# Aether performance stress — {stamp}", "", f"Binary: `{digest}`", "",
             f"App launch: {launch_ms} ms", f"Completed: {completed}/{len(rows)}", "",
             "| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |",
             "| --- | --- | ---: | ---: | ---: | ---: | --- |"]
    for row in rows:
        values = (row.get("dispatchMs"), row.get("toReadyMs"),
                  row.get("fcpMs"), row.get("lcpMs"))
        cells = ["—" if value is None else str(value) for value in values]
        detail = (row.get("finalURL") or row.get("error") or "").replace("|", "\\|")
        lines.append(f"| {row['step']} | {row['status']} | {' | '.join(cells)} | {detail} |")
    overall = summary["all"]
    lines += ["", f"Successful loads: median {overall['medianMs']} ms; "
              f"p95 {overall['p95Ms']} ms; worst {overall['worstMs']} ms.", "",
              "| Metric | Samples | Median ms | p95 ms | Worst ms |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for key, values in overall["metrics"].items():
        lines.append(f"| {key} | {values['count']} | {values['medianMs']} | "
                     f"{values['p95Ms']} | {values['worstMs']} |")
    lines += ["",
              "Ready requires the Aether ready state and reported FCP for the current document. "
              "FCP/LCP use the document "
              "navigation clock; ready time includes command dispatch and polling. "
              "Screenshots are captured after timing."]
    with open(os.path.join(folder, "report.md"), "w", encoding="utf-8") as output:
        output.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rebuild", action="store_true", help="clean build and sign Aether.app")
    parser.add_argument("--timeout", type=float, default=45, help="seconds per navigation")
    parser.add_argument("--repeats", type=int, default=1, help="number of 20-URL passes")
    parser.add_argument("--paired", action="store_true", help="visit each homepage immediately before its route")
    parser.add_argument("--site", choices=tuple(site for site, _, _ in SITES),
                        help="limit each pass to one website and its route")
    parser.add_argument("--no-screenshots", action="store_true", help="skip Aether window captures")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.repeats <= 0:
        parser.error("--repeats must be positive")
    if args.rebuild:
        print("== clean release build ==", flush=True)
        result = command([os.path.join(ROOT, "Scripts", "build_aether_app.sh"), "--clean"], timeout=3600)
        print(result.stdout[-3000:], flush=True)
        if result.returncode:
            log_path = os.path.join(ROOT, "perf-results", "aether_rebuild.log")
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            with open(log_path, "w", encoding="utf-8") as output:
                output.write(result.stdout)
                output.write("\n--- stderr ---\n")
                output.write(result.stderr)
            diagnostics = [line.strip()[:500] for line in result.stderr.splitlines()
                           if "error:" in line or "fatal error" in line or "signal" in line]
            detail = "\n".join(diagnostics[-12:]) or result.stderr[-1000:]
            raise RuntimeError(f"build failed; full log: {log_path}\n{detail}")
    check_build()
    digest = sha256()
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    folder = os.path.join(ROOT, "perf-results", f"aether_perf_{stamp}")
    os.makedirs(folder, exist_ok=True)
    rows = []
    tab_id = None
    launch_ms = None
    try:
        launch_ms = launch()
        print(f"Aether.app ready in {launch_ms} ms; sha256={digest[:16]}...", flush=True)
        print(f"== {args.repeats} pass(es), {'paired' if args.paired else 'homepage batch then route batch'} ==", flush=True)
        for pass_number, index, site, kind, url in url_steps(args.repeats, args.paired, args.site):
            if tab_id is None:
                action = lambda url=url: app("app-open", url)
            else:
                action = lambda id=tab_id, url=url: app("app-navigate", id, url)
            row, created = step(pass_number, index, site, kind, url, action, tab_id,
                                args.timeout, folder, not args.no_screenshots)
            rows.append(row)
            if created:
                tab_id = created
    finally:
        if rows:
            save(folder, stamp, digest, launch_ms, rows)
            print(f"SAVED: {os.path.relpath(folder, ROOT)}", flush=True)
        quit_app()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
