#!/usr/bin/env python3
"""RPC latency baseline for Aether browserd. Unix-socket JSON, one connection per call (matches browserctl)."""
import argparse
import json
import math
import os
import socket
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

HTML = (
    "<!doctype html><title>rpc-bench</title>"
    "<p id='probe'>hello</p>"
    + "".join(f"<div class='row'>Row {i}</div>" for i in range(200))
).encode()


def rpc(path, method, params=None, token=None, timeout=20.0):
    payload = {"id": "bench", "method": method, "params": params or {}}
    raw = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
    t0 = time.perf_counter()
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(timeout)
        client.connect(str(path))
        if token is not None:
            auth = (json.dumps({"id": "auth", "method": "auth", "params": {"token": token}}) + "\n").encode()
            client.sendall(auth)
            _recv_line(client)
        client.sendall(raw)
        data = _recv_line(client)
    t1 = time.perf_counter()
    encode_ms = len(raw) / max(len(raw), 1) * 0  # placeholder; measured separately below
    msg = json.loads(data)
    t2 = time.perf_counter()
    if msg.get("error"):
        raise RuntimeError(f"{method}: {msg['error']}")
    return {
        "wall_ms": (t1 - t0) * 1000.0,
        "decode_ms": (t2 - t1) * 1000.0,
        "request_bytes": len(raw),
        "response_bytes": len(data),
        "result": msg.get("result"),
    }


def _recv_line(client):
    data = bytearray()
    while not data.endswith(b"\n"):
        block = client.recv(65536)
        if not block:
            raise RuntimeError("daemon disconnected")
        data.extend(block)
    return bytes(data)


def encode_microbench(iterations=2000):
    payload = {"id": "x", "method": "page.query", "params": {"page": 1, "selector": "#probe"}}
    raw = json.dumps(payload).encode()
    t0 = time.perf_counter()
    for _ in range(iterations):
        json.loads(raw)
    decode_ms = (time.perf_counter() - t0) * 1000.0
    obj = json.loads(raw)
    t0 = time.perf_counter()
    for _ in range(iterations):
        json.dumps(obj)
    encode_ms = (time.perf_counter() - t0) * 1000.0
    return {
        "iterations": iterations,
        "encode_ms_total": round(encode_ms, 3),
        "decode_ms_total": round(decode_ms, 3),
        "encode_us_each": round(encode_ms * 1000 / iterations, 2),
        "decode_us_each": round(decode_ms * 1000 / iterations, 2),
    }


def summarize(values):
    ordered = sorted(values)
    n = len(ordered)

    def pct(p):
        return ordered[min(n - 1, max(0, math.ceil(n * p) - 1))]

    return {
        "n": n,
        "min_ms": round(ordered[0], 4),
        "p50_ms": round(statistics.median(ordered), 4),
        "p95_ms": round(pct(0.95), 4),
        "p99_ms": round(pct(0.99), 4),
        "max_ms": round(ordered[-1], 4),
    }


def rss_kb(pid):
    try:
        out = subprocess.check_output(["ps", "-o", "rss=", "-p", str(pid)], text=True)
        return int(out.strip())
    except Exception:
        return None


def run_op(call, op, iterations, warmup=3):
    samples = []
    for i in range(warmup + iterations):
        r = op(call)
        if i >= warmup:
            samples.append(r["wall_ms"])
    return summarize(samples)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--iterations", type=int, default=200)
    args = ap.parse_args()

    sock = Path(tempfile.gettempdir()) / f"aether-rpc-bench-{os.getpid()}.sock"
    log_path = Path(args.output).with_suffix(".daemon.log")
    result = {
        "binary": str(Path(args.binary).resolve()),
        "iterations": args.iterations,
        "notes": "one connection per call (browserctl model); wall time includes connect+write+read",
    }
    daemon = subprocess.Popen([args.binary, "--socket", str(sock), "--no-auth"],
                              stdout=log_path.open("w"), stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 15
        while not sock.exists():
            if time.monotonic() > deadline or daemon.poll() is not None:
                raise RuntimeError("daemon failed to start")
            time.sleep(0.05)

        def call(method, **params):
            return rpc(sock, method, params)

        result["encode_decode_microbench"] = encode_microbench()

        result["ping"] = run_op(call, lambda c: c("ping"), args.iterations)

        def with_context(c):
            ctx = c("context.create", name="bench")["result"]["id"]
            return c("context.list")

        result["context_create_list"] = run_op(call, with_context, max(20, args.iterations // 10))

        ctx = call("context.create", name="bench-main")["result"]["id"]
        page = call("page.create", context=ctx, width=1280, height=800)["result"]["id"]

        def load(c):
            return c("page.loadHTML", page=page, html=HTML.decode(), url="https://bench.test/index.html")

        result["page_loadHTML"] = run_op(call, load, max(20, args.iterations // 10))

        call("page.loadHTML", page=page, html=HTML.decode(), url="https://bench.test/index.html")

        def query(c):
            return c("page.query", page=page, selector="#probe")

        result["page_query"] = run_op(call, query, args.iterations)

        def snapshot(c):
            return c("page.snapshot", page=page)

        result["page_snapshot"] = run_op(call, snapshot, max(20, args.iterations // 5))

        def set_cookie(c):
            return c("context.setCookie", context=ctx, url="https://bench.test",
                     name="k", value="v", domain="bench.test", path="/")

        result["context_setCookie"] = run_op(call, set_cookie, max(20, args.iterations // 10))

        def list_cookies(c):
            return c("context.cookies", context=ctx)

        result["context_cookies"] = run_op(call, list_cookies, args.iterations)

        result["browserd_rss_kb"] = rss_kb(daemon.pid)
        result["ok"] = True
    except Exception as exc:
        result["ok"] = False
        result["error"] = str(exc)
    finally:
        daemon.terminate()
        try:
            daemon.wait(timeout=5)
        except subprocess.TimeoutExpired:
            daemon.kill()
        if sock.exists():
            sock.unlink(missing_ok=True)

    Path(args.output).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "notes"}, indent=2, sort_keys=True))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
