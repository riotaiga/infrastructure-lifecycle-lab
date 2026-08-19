#!/bin/bash

set -euo pipefail

readonly PXE_CONFIG_DIR="/opt/pxe"
readonly TFTP_ROOT="/srv/tftp"
readonly HTTP_ROOT="/var/www/html/ubuntu"
readonly PXE_STATE_DIR="/var/lib/pxe"
readonly UBUNTU_VERSION="24.04.4"
readonly UBUNTU_ISO="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
readonly UBUNTU_RELEASE_URL="https://releases.ubuntu.com/24.04"
readonly UBUNTU_ISO_URL="${UBUNTU_RELEASE_URL}/${UBUNTU_ISO}"
readonly UBUNTU_SUMS_URL="${UBUNTU_RELEASE_URL}/SHA256SUMS"

echo "=== Configuring the PXE service ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 ca-certificates curl dnsmasq libarchive-tools \
  pxelinux syslinux-common tftpd-hpa

install -d -m 0755 "${TFTP_ROOT}/pxelinux.cfg"
install -d -m 0755 "${TFTP_ROOT}/ubuntu-24.04"
install -d -m 0755 "${HTTP_ROOT}" "${PXE_STATE_DIR}" /var/lib/pxe/clients
touch /etc/dnsmasq.d/pxe-installed.conf
chmod 0644 /etc/dnsmasq.d/pxe-installed.conf

# Debian-family packages put these files in architecture-dependent locations.
PXELINUX_BIN="$(find /usr/lib -type f -name pxelinux.0 -print -quit)"
MENU_BIN="$(find /usr/lib -type f -name menu.c32 -print -quit)"

if [[ -z "${PXELINUX_BIN}" || -z "${MENU_BIN}" ]]; then
  echo "PXELINUX boot files were not installed." >&2
  exit 1
fi

install -m 0644 "${PXELINUX_BIN}" "${TFTP_ROOT}/pxelinux.0"
install -m 0644 "${MENU_BIN}" "${TFTP_ROOT}/menu.c32"
# menu.c32 loads additional modules at boot.  Install all BIOS modules from
# the same syslinux package so the PXE loader and its modules stay compatible.
MODULE_DIR="$(dirname "${MENU_BIN}")"
find "${MODULE_DIR}" -maxdepth 1 -type f -name '*.c32' -exec install -m 0644 {} "${TFTP_ROOT}" \;
install -m 0644 "${PXE_CONFIG_DIR}/pxelinux.cfg/default" \
  "${TFTP_ROOT}/pxelinux.cfg/default"
install -m 0644 "${PXE_CONFIG_DIR}/dnsmasq.conf" /etc/dnsmasq.d/pxe.conf

ISO_PATH="${PXE_STATE_DIR}/${UBUNTU_ISO}"
SUMS_PATH="${PXE_STATE_DIR}/SHA256SUMS"

echo "Downloading and verifying Ubuntu ${UBUNTU_VERSION} Server ISO..."
curl --fail --location --retry 3 --output "${SUMS_PATH}" "${UBUNTU_SUMS_URL}"
if [[ ! -f "${ISO_PATH}" ]]; then
  curl --fail --location --retry 3 --output "${ISO_PATH}" "${UBUNTU_ISO_URL}"
fi

# Verify the precise release before exposing it to PXE clients.  The checksum
# list comes directly from Ubuntu's release site over HTTPS.
grep -F " *${UBUNTU_ISO}" "${SUMS_PATH}" | (cd "${PXE_STATE_DIR}" && sha256sum -c -)

# Keep the TFTP boot files tied to the same verified ISO served over HTTP.
bsdtar -xOf "${ISO_PATH}" casper/vmlinuz >"${TFTP_ROOT}/ubuntu-24.04/vmlinuz"
bsdtar -xOf "${ISO_PATH}" casper/initrd >"${TFTP_ROOT}/ubuntu-24.04/initrd"
chmod 0644 "${TFTP_ROOT}/ubuntu-24.04/vmlinuz" "${TFTP_ROOT}/ubuntu-24.04/initrd"
ln -sfn "${ISO_PATH}" "${HTTP_ROOT}/${UBUNTU_ISO}"

cat >/etc/default/tftpd-hpa <<'EOF'
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="10.20.30.1:69"
TFTP_OPTIONS="--secure --ipv4"
EOF

# add dnsmasq validation to see if its working..
dnsmasq --test

systemctl restart tftpd-hpa
systemctl restart dnsmasq
systemctl enable --now apache2

echo "=== PXE service is ready on 10.20.30.1 ==="
echo "Ubuntu ISO: http://10.20.30.1/ubuntu/${UBUNTU_ISO}"