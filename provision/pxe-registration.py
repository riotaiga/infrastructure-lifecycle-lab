#!/usr/bin/env python3
#
# PXE registration service (runs on the control node).
#
# After a PXE client finishes autoinstall, it POSTs its MAC address here.
# We mark that MAC as "installed" so dnsmasq stops offering the installer
# on the next boot. The client then falls through to disk boot.

from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import subprocess

# One empty file per installed client MAC (filename = mac without separators).
STATE_DIR = Path("/var/lib/pxe/clients")

# dnsmasq reads this file; each line tags a MAC as "installed".
DNSMASQ_INSTALLED = Path("/etc/dnsmasq.d/pxe-installed.conf")

# Per-MAC pxelinux configs (backup if a client still loads pxelinux).
TFTP_MAC_CFG_DIR = Path("/srv/tftp/pxelinux.cfg")

# pxelinux menu for installed clients: boot local disk immediately.
PXELINUX_LOCAL_TEMPLATE = """DEFAULT local
PROMPT 0
TIMEOUT 10
ONTIMEOUT local

LABEL local
  MENU LABEL Boot from local disk
  LOCALBOOT 0
"""


def normalize_mac(mac: str) -> str:
    # Accept 08:00:27:ab:cd:ef or 08-00-27-ab-cd-ef → 080027abcdef
    return mac.lower().replace(":", "").replace("-", "")


def mac_to_pxelinux_name(mac: str) -> str:
    # pxelinux looks for configs named 01-<mac-with-dashes>, e.g. 01-08-00-27-ab-cd-ef
    cleaned = normalize_mac(mac)
    return f"01-{'-'.join(cleaned[i:i + 2] for i in range(0, 12, 2))}"


def mac_to_dnsmasq(mac: str) -> str:
    # dnsmasq expects colon-separated MAC, e.g. 08:00:27:ab:cd:ef
    cleaned = normalize_mac(mac)
    return ":".join(cleaned[i:i + 2] for i in range(0, 12, 2))


def rebuild_dnsmasq_installed() -> None:
    # Rebuild the installed-host list from marker files on disk.
    # Each entry tells dnsmasq: this MAC has tag "installed" (no PXE boot file).
    lines = []
    for marker in sorted(STATE_DIR.glob("*")):
        if marker.is_file() and len(marker.name) == 12:
            mac = mac_to_dnsmasq(marker.name)
            lines.append(f"dhcp-host={mac},set:installed\n")

    DNSMASQ_INSTALLED.write_text("".join(lines))


def register_client(mac: str) -> None:
    # Record install complete (inventory only). Boot order is disk-first on the
    # client, so we do not change dnsmasq or pxelinux — that broke fresh installs.
    mac_norm = normalize_mac(mac)

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (STATE_DIR / mac_norm).touch()

    print(f"PXE installation completed: {mac_to_dnsmasq(mac_norm)}")


class Handler(BaseHTTPRequestHandler):
    # Handle POST /install-complete with JSON body: {"mac": "08:00:27:..."}

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
        # Print HTTP access logs to journalctl instead of stderr default.
        print(format % args)


if __name__ == "__main__":
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    # Listen on the PXE LAN interface only (same subnet as dnsmasq/TFTP).
    server = HTTPServer(("10.20.30.1", 8080), Handler)
    print("PXE registration server listening on 10.20.30.1:8080")
    server.serve_forever()
