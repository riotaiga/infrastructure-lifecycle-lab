#!/usr/bin/env python3

from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import subprocess

STATE_DIR = Path("/var/lib/pxe/clients")
DNSMASQ_INSTALLED = Path("/etc/dnsmasq.d/pxe-installed.conf")
TFTP_MAC_CFG_DIR = Path("/srv/tftp/pxelinux.cfg")

PXELINUX_LOCAL_TEMPLATE = """DEFAULT local
PROMPT 0
TIMEOUT 10
ONTIMEOUT local

LABEL local
  MENU LABEL Boot from local disk
  LOCALBOOT 0
"""


def normalize_mac(mac: str) -> str:
    return mac.lower().replace(":", "").replace("-", "")


def mac_to_pxelinux_name(mac: str) -> str:
    cleaned = normalize_mac(mac)
    return f"01-{'-'.join(cleaned[i:i + 2] for i in range(0, 12, 2))}"


def mac_to_dnsmasq(mac: str) -> str:
    cleaned = normalize_mac(mac)
    return ":".join(cleaned[i:i + 2] for i in range(0, 12, 2))


def rebuild_dnsmasq_installed() -> None:
    lines = []
    for marker in sorted(STATE_DIR.glob("*")):
        if marker.is_file() and len(marker.name) == 12:
            mac = mac_to_dnsmasq(marker.name)
            lines.append(f"dhcp-host={mac},set:installed\n")

    DNSMASQ_INSTALLED.write_text("".join(lines))


def register_client(mac: str) -> None:
    mac_norm = normalize_mac(mac)

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (STATE_DIR / mac_norm).touch()

    TFTP_MAC_CFG_DIR.mkdir(parents=True, exist_ok=True)
    pxelinux_cfg = TFTP_MAC_CFG_DIR / mac_to_pxelinux_name(mac)
    pxelinux_cfg.write_text(PXELINUX_LOCAL_TEMPLATE)

    rebuild_dnsmasq_installed()
    subprocess.run(["systemctl", "reload", "dnsmasq"], check=True)

    print(f"PXE installation completed: {mac_to_dnsmasq(mac_norm)}")


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

        try:
            register_client(mac)
        except Exception as exc:
            print(f"Registration failed for {mac}: {exc}")
            self.send_response(500)
            self.end_headers()
            return

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, format, *args):
        print(format % args)


if __name__ == "__main__":
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DNSMASQ_INSTALLED.parent.mkdir(parents=True, exist_ok=True)
    if not DNSMASQ_INSTALLED.exists():
        DNSMASQ_INSTALLED.touch()

    rebuild_dnsmasq_installed()

    server = HTTPServer(("10.20.30.1", 8080), Handler)
    print("PXE registration server listening on 10.20.30.1:8080")
    server.serve_forever()
