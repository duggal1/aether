#!/usr/bin/env python3
"""Warm-profile, sequential time-to-observed-title benchmark for Safari/Chrome/Aether.

This is NOT exact first-paint or exact title-transition timing. The observation
includes the dispatch/probe overhead and is an upper bound on title visibility.
Never treat the result as an FCP or browser-engine performance measurement.
"""

import argparse
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

SITES = [
    "https://www.see-for-yourself.com/",
    "https://www.dontlookup.app/",
    "https://wisprflow.ai/",
    "https://tryclico.com/",
    "https://www.boonglobal.io/",
    "https://www.moremedia.at/",
    "https://www.corndel.com/",
    "https://www.podiumautomation.com/",
    "https://usealia.com/",
    "https://calendly.com/",
    "https://www.clay.com/",
    "https://www.apollo.io/",
    "https://instantly.ai/",
    "https://eatsnackish.com/",
    "https://playfolly.com/",
    "https://www.lyleandscott.com/",
]

BAD_TITLES = {"", "untitled", "new tab", "start page", "loading", "about:blank"}
SEPARATOR = chr(31)


def now_ns():
    return time.perf_counter_ns()


def elapsed_ms(start_ns):
    return round((now_ns() - start_ns) / 1_000_000, 2)


def run_checked(cmd, timeout=30):
    p = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError(f"{' '.join(cmd[:2])}: {p.stderr.strip() or p.stdout.strip()}")
    # NOTE: rstrip newline only. str.strip() would eat \x1e/\x1f separators
    # (they classify as whitespace), corrupting tab-state records whose URL
    # is empty (e.g. fresh about:blank tabs report missing URL).
    return p.stdout.rstrip("\n")


def osa(script, timeout=30):
    return run_checked(["osascript", "-e", script], timeout=timeout)


def ctl(args, *parts, timeout=30):
    stdout = run_checked([args.ctl, "--socket", args.socket, *map(str, parts)], timeout=timeout)
    message = None
    for line in stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
    if not isinstance(message, dict):
        raise RuntimeError(f"browserctl did not emit a JSON object: {stdout[-300:]}")
    if message.get("error"):
        raise RuntimeError(f"browserctl error: {message['error']}")
    return message.get("result")


def canonical_host(url):
    host = (urlsplit(url).hostname or "").lower().rstrip(".")
    return host[4:] if host.startswith("www.") else host


def title_belongs_to_target(observed_url, title, expected_url):
    title = (title or "").strip()
    if not title or title.casefold() in BAD_TITLES:
        return False
    actual_host = canonical_host(observed_url)
    expected_host = canonical_host(expected_url)
    if not actual_host or not (actual_host == expected_host or actual_host.endswith("." + expected_host)):
        return False
    # Site URL placeholders are NOT page titles. Never accept a previous-tab title.
    if title.lower().startswith(("http://", "https://")):
        return False
    if title.casefold() == (observed_url or "").strip().casefold():
        return False
    return True


def desktop_app(which):
    return "Safari" if which == "safari" else "Google Chrome"


def prepare_desktop(app):
    # Intentionally no pkill -9 and no fake cold-start timing.
    # Apple Events permission prompts must be resolved BEFORE starting trials.
    if app == "Safari":
        osa('tell application "Safari"\nif (count of windows) is 0 then make new document\nreturn count of windows\nend tell')
    else:
        osa('tell application "Google Chrome"\nif (count of windows) is 0 then make new window\nreturn count of windows\nend tell')


def fresh_desktop_tab(app):
    if app == "Safari":
        script = ('tell application "Safari"\n'
                  'tell window 1\n'
                  'set freshTab to make new tab with properties {URL:"about:blank"}\n'
                  'set current tab to freshTab\n'
                  'return (count of tabs)\n'
                  'end tell\nend tell')
    else:
        script = ('tell application "Google Chrome"\n'
                  'tell window 1\n'
                  'set freshTab to make new tab with properties {URL:"about:blank"}\n'
                  'set active tab index to (count of tabs)\n'
                  'return (count of tabs)\n'
                  'end tell\nend tell')
    return int(osa(script))


def desktop_state(app, index):
    # Fetch URL+title atomically from ONE tab in ONE Apple Event.
    script = (f'tell application "{app}"\n'
              f'  set tabURL to URL of tab {index} of window 1\n'
              f'  set tabTitle to name of tab {index} of window 1\n'
              '  if tabURL is missing value then set tabURL to ""\n'
              '  if tabTitle is missing value then set tabTitle to ""\n'
              '  return (tabURL as text) & (character id 31) & (tabTitle as text)\n'
              'end tell') if app == "Safari" else (
              f'tell application "{app}"\n'
              f'  set tabURL to URL of tab {index} of window 1\n'
              f'  set tabTitle to title of tab {index} of window 1\n'
              '  if tabURL is missing value then set tabURL to ""\n'
              '  if tabTitle is missing value then set tabTitle to ""\n'
              '  return (tabURL as text) & (character id 31) & (tabTitle as text)\n'
              'end tell')
    result = osa(script)
    if SEPARATOR not in result:
        raise RuntimeError(f"Malformed AppleScript tab state: {result!r}")
    return result.split(SEPARATOR, 1)


def wait_for_blank(app, index):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        url, title = desktop_state(app, index)
        # Fresh about:blank tabs report a missing URL; accept empty too.
        if url.strip().lower() in ("about:blank", ""):
            return
        time.sleep(0.05)
    raise RuntimeError(f"Cannot establish blank-tab baseline (tab {index}, {app})")


def dispatch_desktop(app, index, url):
    property_name = "URL"
    # Run asynchronously: AppleScript may block until well into navigation.
    script = (f'tell application "{app}" to set {property_name} of '
              f'tab {index} of window 1 to {json.dumps(url)}')
    return subprocess.Popen(["osascript", "-e", script],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def aether_state(args, ctx, pid):
    pages = ctl(args, "page-list", ctx, timeout=20)
    if not isinstance(pages, list):
        raise RuntimeError(f"Unexpected page-list response: {str(pages)[:200]}")
    for page in pages:
        if str(page.get("id")) == str(pid):
            return page.get("url") or "", page.get("title") or ""
    raise RuntimeError(f"Page {pid} vanished from context {ctx}")


def aether_tab(args, ctx):
    page = ctl(args, "page-create", ctx)
    if not isinstance(page, dict) or "id" not in page:
        raise RuntimeError(f"Unexpected page-create response: {page}")
    pid = page["id"]
    aether_state(args, ctx, pid)  # The page exists before the clock starts.
    return pid


def dispatch_aether(args, pid, url):
    # Keep existing CLI syntax. If this command blocks until load, the clock
    # still includes it because subprocess.Popen returns before completion.
    return subprocess.Popen(
        [args.ctl, "--socket", args.socket, "page-navigate-input", str(pid), url],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def finish_dispatch(proc):
    if proc.poll() is None:
        return "pending"
    output, error = proc.communicate(timeout=2)
    if proc.returncode:
        return f"ERROR: {(error or output).strip()[:250]}"
    return "ok"


def cleanup_dispatch(proc):
    if proc.poll() is None:
        # Do not kill the browser, just terminate a hung automation CLI.
        proc.terminate()
        try:
            proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate(timeout=2)
    else:
        proc.communicate(timeout=2)


DAEMON = {"proc": None, "ctx": None, "restarts": 0}

def start_daemon(args):
    subprocess.run(["rm", "-f", args.socket])
    DAEMON["proc"] = subprocess.Popen(
        [args.ctl.replace("browserctl", "browserd"), "--socket", args.socket, "--no-auth"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL, start_new_session=True)
    for _ in range(100):
        time.sleep(0.1)
        try:
            if ctl(args, "ping", timeout=5):
                break
        except Exception:
            pass
    ctx_result = ctl(args, "context-create", "sequential-benchmark")
    DAEMON["ctx"] = ctx_result["id"]
    return DAEMON["ctx"]


def ensure_daemon(args):
    alive = False
    try:
        alive = bool(ctl(args, "ping", timeout=5))
    except Exception:
        alive = False
    if not alive or DAEMON["ctx"] is None:
        DAEMON["restarts"] += 1
        try:
            if DAEMON["proc"] is not None and DAEMON["proc"].poll() is None:
                DAEMON["proc"].kill()
        except Exception:
            pass
        return start_daemon(args)
    return DAEMON["ctx"]


def sample_once(args, which, app, ctx, url):
    if app is None:
        ctx = ensure_daemon(args)
    index_or_pid = fresh_desktop_tab(app) if app else aether_tab(args, ctx)
    try:
        if app:
            wait_for_blank(app, index_or_pid)
        probe = (lambda: desktop_state(app, index_or_pid)) if app else (
            lambda: aether_state(args, ctx, index_or_pid))
        started = now_ns()  # BEFORE either navigation subprocess is launched.
        proc = dispatch_desktop(app, index_or_pid, url) if app else (
            dispatch_aether(args, index_or_pid, url))
        try:
            deadline_ns = started + int(args.timeout * 1_000_000_000)
            last_negative_ns = started
            samples = 0
            last_url, last_title = "", ""
            last_probe_ms = 0.0
            while now_ns() < deadline_ns:
                probe_started = now_ns()
                try:
                    last_url, last_title = probe()
                except (RuntimeError, subprocess.TimeoutExpired) as exc:
                    # A transient navigation race is okay, but preserve failures.
                    if proc.poll() is not None and proc.returncode:
                        raise RuntimeError(f"Navigation command failed: {finish_dispatch(proc)}") from exc
                    time.sleep(args.interval)
                    continue
                last_probe_ms = round((now_ns() - probe_started) / 1_000_000, 2)
                samples += 1
                if title_belongs_to_target(last_url, last_title, url):
                    elapsed = elapsed_ms(started)
                    status = finish_dispatch(proc)
                    if status.startswith("ERROR:"):
                        return {"url": url, "status": "ERROR", "error": status}
                    return {"url": url, "status": "OK", "observed_title_ms": elapsed,
                            "title_lower_bound_ms": round((last_negative_ns - started) / 1_000_000, 2),
                            "title": last_title, "observed_url": last_url,
                            "samples": samples, "last_probe_ms": last_probe_ms,
                            "dispatch": status}
                last_negative_ns = now_ns()
                status = finish_dispatch(proc)
                if status.startswith("ERROR:"):
                    return {"url": url, "status": "ERROR", "error": status,
                            "observed_url": last_url, "title": last_title}
                time.sleep(args.interval)
            return {"url": url, "status": "TIMEOUT", "elapsed_ms": elapsed_ms(started),
                    "observed_url": last_url, "title": last_title, "samples": samples,
                    "last_probe_ms": last_probe_ms, "dispatch": finish_dispatch(proc)}
        finally:
            cleanup_dispatch(proc)
    finally:
        if app:
            try:
                osa(f'tell application "{app}" to close tab {index_or_pid} of window 1')
            except (RuntimeError, subprocess.TimeoutExpired):
                pass
        else:
            try:
                ctl(args, "page-close", index_or_pid, timeout=10)
            except (RuntimeError, subprocess.TimeoutExpired):
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("which", choices=["safari", "chrome", "aether"])
    parser.add_argument("--trials", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--interval", type=float, default=0.05)
    parser.add_argument("--socket", default="/tmp/aether-t10.sock")
    parser.add_argument("--ctl", default=".build/release/browserctl")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()
    if args.trials < 1 or args.timeout <= 0 or args.interval < 0:
        parser.error("trials and timeout must be positive; interval cannot be negative")

    app = None if args.which == "aether" else desktop_app(args.which)
    if app:
        prepare_desktop(app)
        ctx = None
    else:
        ctx = start_daemon(args)

    import os
    only = [u for u in os.environ.get("AETHER_ONLY", "").split(",") if u]
    sites = [u for u in SITES if (not only or u in only)]
    results = []
    for trial in range(1, args.trials + 1):
        for url in sites:
            try:
                result = sample_once(args, args.which, app, ctx, url)
            except (RuntimeError, subprocess.TimeoutExpired, OSError, ValueError) as exc:
                result = {"url": url, "status": "ERROR", "error": str(exc)}
            result["trial"] = trial
            results.append(result)
            label = (f"{result['observed_title_ms']:.2f} ms" if result["status"] == "OK"
                     else result["status"])
            print(f"{args.which:6s} trial={trial} {label:>13s} {url} "
                  f"{result.get('title', result.get('error', ''))[:55]}", flush=True)

    ok = [r["observed_title_ms"] for r in results if r["status"] == "OK"]
    summary = {"count_ok": len(ok), "count_total": len(results),
               "median_observed_title_ms": round(statistics.median(ok), 2) if ok else None,
               "daemon_restarts": DAEMON["restarts"]}
    output = args.output or f"/tmp/aether-seq-{args.which}-fixed.json"
    Path(output).write_text(json.dumps({
        "metric": "dispatch-to-observed-title; includes CLI/AppleScript probe overhead; NOT FCP",
        "browser": args.which, "mode": "warm profile, fresh blank tab each navigation",
        "summary": summary, "results": results,
    }, indent=2), encoding="utf-8")
    print(f"SUMMARY {summary} | {output}")
    if len(ok) != len(results):
        print("WARNING: missing/failed trials are not included in median", file=sys.stderr)


if __name__ == "__main__":
    main()
