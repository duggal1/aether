#!/usr/bin/env python3
"""Drive an isolated instrumented AetherApp and report per-stage latency.

Runs the release binary directly (unsandboxed: its own temp socket dir and its
own profile directory), so it never touches a packaged .app instance.
"""
import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time

ROOT = "/Users/harshitduggal/workspace/Aether"
BIN = os.path.join(ROOT, ".build/release/AetherApp")
CTL = os.path.join(ROOT, ".build/release/browserctl")
SOCKET_DIR = os.path.join(tempfile.gettempdir(), "aether-agent")
LOG = "/tmp/aether-latency.log"


def socket_ready(path, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            result = subprocess.run([CTL, "--socket", path, "app-status"],
                                    capture_output=True, text=True, timeout=20)
            if result.returncode == 0 and "\"ready\"" in result.stdout:
                return True
        time.sleep(0.05)
    return False


def send(socket, *args, timeout=60):
    result = subprocess.run([CTL, "--socket", socket, *args],
                            capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr.strip()[:300])
    payload = json.loads(result.stdout)
    if payload.get("error"):
        raise RuntimeError(str(payload["error"])[:300])
    return payload.get("result")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("urls", nargs="+")
    parser.add_argument("--mode", choices=("open", "navigate"), default="open",
                        help="open = new tab per URL (app-open), navigate = reuse first tab")
    parser.add_argument("--socket-name", default="browser.sock")
    args = parser.parse_args()

    socket = os.path.join(SOCKET_DIR, args.socket_name)
    for suffix in ("", ".lock"):
        try:
            os.unlink(socket + suffix)
        except FileNotFoundError:
            pass
    environment = dict(os.environ, AETHER_LATENCY_DIAG="1", AETHER_WEBKIT_DIAG="1")
    with open(LOG, "w") as log:
        process = subprocess.Popen([BIN], stdout=log, stderr=log, env=environment,
                                   cwd=ROOT, start_new_session=True)
    launched = time.time()
    try:
        if not socket_ready(socket):
            raise RuntimeError("app never became ready on the automation socket")
        print("launch_to_socket_ready_ms=%.1f" % ((time.time() - launched) * 1000), flush=True)
        marks = []
        if args.mode == "open":
            for url in args.urls:
                started = time.time()
                tab = send(socket, "app-open", url)
                marks.append(("open", url, started, tab["id"]))
        else:
            tabs = send(socket, "app-tabs")
            tab_id = tabs[0]["id"]
            for url in args.urls:
                started = time.time()
                send(socket, "app-navigate", tab_id, url)
                marks.append(("navigate", url, started, tab_id))
        for kind, url, started, tab_id in marks:
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                tab = next((t for t in send(socket, "app-tabs") if t["id"] == tab_id), None)
                if tab is None:
                    break
                try:
                    metrics = send(socket, "app-metrics", tab_id)
                except RuntimeError:
                    metrics = {}
                if metrics.get("fcpMs") is not None:
                    print("%-9s %-52s wall=%7.0fms fcp=%6s state=%s" % (
                        kind, url[:52], (time.time() - started) * 1000,
                        metrics.get("fcpMs"), tab.get("state")), flush=True)
                    break
                time.sleep(0.05)
    finally:
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass
        time.sleep(1.0)
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass

    timeline = []
    with open(LOG) as log:
        for line in log:
            timeline.append(line.rstrip())
    for line in timeline:
        if "[latency]" in line or "[webkit-nav]" in line:
            print(line, flush=True)


if __name__ == "__main__":
    sys.exit(main())
