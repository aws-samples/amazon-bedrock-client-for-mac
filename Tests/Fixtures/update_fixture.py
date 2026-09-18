#!/usr/bin/env python3
"""Loopback download fixture; never proxies a public release or installs an app."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import TCPServer
import signal
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


class DownloadFixture(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)

    def server_bind(self):
        # HTTPServer's reverse DNS lookup can open a macOS local-network
        # consent dialog. This fixture only serves literal loopback traffic.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


if __name__ == "__main__":
    # A fixture launched from a cooperative XCTest worker can inherit blocked
    # signals. Restore normal termination before publishing the ready port.
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    signal.pthread_sigmask(signal.SIG_SETMASK, [])
    with DownloadFixture() as server:
        ready = Path(sys.argv[1])
        pending = ready.with_name(ready.name + ".tmp")
        pending.write_text(str(server.server_port))
        pending.replace(ready)
        server.serve_forever()
