"""Native browserd authorization smoke: real Unix socket, separate client connections."""
import argparse
import json
import pathlib
import socket
import subprocess
import tempfile
import time


def rpc(path, method, **params):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(15)
        client.connect(str(path))
        payload = {"id": "authority-smoke", "method": method, "params": params}
        client.sendall((json.dumps(payload) + "\n").encode())
        response = bytearray()
        while not response.endswith(b"\n"):
            part = client.recv(65536)
            if not part:
                raise RuntimeError("daemon disconnected without a response")
            response.extend(part)
    return json.loads(response)


def require_ok(response):
    assert response.get("error") is None, response
    return response["result"]


def require_denied(response):
    assert response.get("error", {}).get("code") == "unauthorized", response


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", default=".build/release")
    args = parser.parse_args()
    daemon_path = pathlib.Path(args.bin).resolve() / "browserd"
    with tempfile.TemporaryDirectory(prefix="aether-auth-") as directory:
        path = pathlib.Path(directory) / "browserd.sock"
        daemon = subprocess.Popen(
            [str(daemon_path), "--socket", str(path)],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 15
            while not path.exists() and time.monotonic() < deadline:
                if daemon.poll() is not None:
                    raise RuntimeError("browserd exited while starting")
                time.sleep(0.05)
            assert path.exists(), "browserd socket not created"
            require_ok(rpc(path, "ping"))
            a = require_ok(rpc(path, "context.create", name="principal-a"))
            b = require_ok(rpc(path, "context.create", name="principal-b"))
            token_a, token_b = a["capability"], b["capability"]
            assert token_a != token_b and len(token_a) >= 64
            require_denied(rpc(path, "context.list"))
            require_denied(rpc(path, "context.cookies", context=b["id"],
                capability=token_a, owner="principal-b"))
            a_list = require_ok(rpc(path, "context.list", capability=token_a))
            assert [x["id"] for x in a_list] == [a["id"]], a_list
            page = require_ok(rpc(path, "page.create",
                context=b["id"], capability=token_b))
            require_ok(rpc(path, "page.loadHTML", page=page["id"],
                capability=token_b, url="https://fixture.test/",
                html="<html><head><title>Auth fixture</title></head><body>ok</body></html>"))
            require_denied(rpc(path, "page.inspect", page=page["id"],
                capability=token_a, owner="principal-b"))
            require_ok(rpc(path, "page.inspect", page=page["id"],
                capability=token_b))
            require_denied(rpc(path, "context.openProfile", context=b["id"],
                capability=token_b, directory="/tmp/untrusted-profile"))
            require_denied(rpc(path, "context.download", context=b["id"],
                capability=token_b, url="https://example.test/",
                path="/tmp/sensitive-target"))
            require_ok(rpc(path, "context.destroy",
                context=b["id"], capability=token_b))
            assert require_ok(rpc(path, "context.list", capability=token_b)) == []
            print("PASS: scoped capabilities, cross-context denial, forged-owner denial, revocation, sensitive-path denial")
        finally:
            daemon.terminate()
            try:
                daemon.wait(timeout=5)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait()


if __name__ == "__main__":
    main()
