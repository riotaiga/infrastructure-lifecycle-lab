#!/bin/bash

set -euo pipefail

readonly PXE_SUBNET="10.20.30.0/24"
readonly SYSCTL_CONF="/etc/sysctl.d/99-pxe-forward.conf"

echo "=== Configuring PXE LAN gateway (NAT through control) ==="

export DEBIAN_FRONTEND=noninteractive
apt-get install -y iptables iptables-persistent netfilter-persistent

# Allow the control node to forward packets between interfaces.
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >"${SYSCTL_CONF}"

# Internet-facing NIC (Vagrant NAT / default route).
OUT_IF="$(ip -4 route show default | awk '{print $5; exit}')"
if [[ -z "${OUT_IF}" ]]; then
  echo "No default route found on control; cannot configure NAT." >&2
  exit 1
fi

# PXE LAN NIC (the interface that owns 10.20.30.1).
PXE_IF="$(ip -4 addr show | awk '/10\.20\.30\.1\// {print $NF; exit}')"
if [[ -z "${PXE_IF}" ]]; then
  echo "PXE interface (10.20.30.1) not found on control." >&2
  exit 1
fi

echo "PXE interface: ${PXE_IF}, upstream interface: ${OUT_IF}"

iptables -t nat -C POSTROUTING -s "${PXE_SUBNET}" -o "${OUT_IF}" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "${PXE_SUBNET}" -o "${OUT_IF}" -j MASQUERADE

iptables -C FORWARD -i "${PXE_IF}" -o "${OUT_IF}" -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "${PXE_IF}" -o "${OUT_IF}" -j ACCEPT

iptables -C FORWARD -i "${OUT_IF}" -o "${PXE_IF}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "${OUT_IF}" -o "${PXE_IF}" -m state --state RELATED,ESTABLISHED -j ACCEPT

netfilter-persistent save

echo "=== PXE LAN gateway ready (${PXE_SUBNET} -> ${OUT_IF}) ==="
