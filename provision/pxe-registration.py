#!/usr/bin/env python3

# PXE Installation Registration Server 
# runs on control node, PXE client will send its MAC address 
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json

STATE_DIR = Path("/var/lib/pxe/clients")
STATE_DIR.mkdir(parents=True, exist_ok=True)

class Handler(BaseHTTPRequestHandler):

    def do_POST(self):
        if self.path != "/install-complete":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(length)

        try:
            payload = json.loads(data.decode())
        except Exception:
            self.send_response(400)
            self.end_headers()
            return

        mac = payload.get("mac")

        if not mac:
            self.send_response(400)
            self.end_headers()
            return

        mac = mac.lower().replace(":", "")

        marker = STATE_DIR / mac
        marker.touch()

        print(f"PXE installation completed: {mac}")

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

server = HTTPServer(("10.20.30.1", 8080), Handler)

print("PXE registration server listening on 10.20.30.1:8080")

server.serve_forever()