#!/usr/bin/env python3
"""Control surface for an interactive simulator session.

Why a proxy instead of talking to the app directly: the app's debug server
answers on 127.0.0.1:8321, which is only reachable from the runner itself, and
its responses carry no CORS headers, so a browser pointed straight at it from
another origin would be blocked. This process serves the console page and
forwards JSON-RPC same-origin, and it turns debug.screenshot into a plain PNG
body so the page can poll it through an <img>.

Security note: the debug server's auth is turned OFF for these throwaway
sessions (see the workflow), so whoever holds the tunnel URL can drive the app.
The URL is unguessable and dies with the job; do not put personal data into a
session started this way.
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RPC_URL = os.environ.get("RPC_URL", "http://127.0.0.1:8321/rpc")
SCHEMA_URL = os.environ.get("SCHEMA_URL", "http://127.0.0.1:8321/schema")
HERE = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PORT", "8322"))
# Must match SHOT_SCALE in console.html: the page divides pixel coordinates by
# this to get points, so a mismatch would make every tap land near-but-wrong.
SHOT_SCALE = 2.0


def post_rpc(raw: bytes) -> tuple[int, bytes]:
    request = urllib.request.Request(
        RPC_URL, data=raw, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            return 200, response.read()
    except urllib.error.HTTPError as failure:
        return failure.code, failure.read() or b'{"error":"upstream http error"}'
    except Exception as failure:  # noqa: BLE001 - surfaced to the page verbatim
        return 502, json.dumps({"error": str(failure)}).encode()


def fetch_screenshot() -> tuple[int, bytes]:
    payload = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "debug.screenshot",
            "params": {"scale": SHOT_SCALE},
        }
    ).encode()
    status, body = post_rpc(payload)
    if status != 200:
        return status, body
    try:
        parsed = json.loads(body.decode("utf-8"))
        encoded = parsed["result"]["base64"]
    except Exception:  # noqa: BLE001 - the page shows whatever went wrong
        return 502, body
    return 200, base64.b64decode(encoded)


class Handler(BaseHTTPRequestHandler):
    server_version = "MinisConsole/1"

    def log_message(self, fmt, *args):  # keep the CI log readable
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
        path = self.path.partition("?")[0]
        if path in ("/", "/index.html"):
            with open(os.path.join(HERE, "console.html"), "rb") as handle:
                self._send(200, handle.read(), "text/html; charset=utf-8")
            return
        if path == "/shot":
            status, body = fetch_screenshot()
            if status == 200:
                self._send(200, body, "image/png")
            else:
                self._send(status, body, "application/json; charset=utf-8")
            return
        if path == "/schema":
            try:
                with urllib.request.urlopen(SCHEMA_URL, timeout=10) as response:
                    self._send(200, response.read(), "application/json; charset=utf-8")
            except Exception as failure:  # noqa: BLE001
                self._send(502, json.dumps({"error": str(failure)}).encode(),
                           "application/json; charset=utf-8")
            return
        self._send(404, b'{"error":"not found"}', "application/json; charset=utf-8")

    def do_POST(self):  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path.partition("?")[0] != "/rpc":
            self._send(404, b'{"error":"not found"}', "application/json; charset=utf-8")
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length > 0 else b""
        try:
            json.loads(raw.decode("utf-8"))
        except Exception:
            self._send(400, b'{"error":"body is not JSON"}',
                       "application/json; charset=utf-8")
            return
        status, body = post_rpc(raw)
        self._send(status, body, "application/json; charset=utf-8")


def main() -> int:
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"minis console on http://127.0.0.1:{PORT} -> {RPC_URL}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
