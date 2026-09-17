#!/usr/bin/env python3
"""Loopback download fixture; never proxies a public release or installs an app."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys

PAYLOAD = b"verified update payload"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        status = 200 if self.path == "/update.dmg" else 404
        body = PAYLOAD if status == 200 else b"not a release"
        self.send_response(status)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        Path(sys.argv[1]).write_text(str(server.server_port))
        server.serve_forever()
