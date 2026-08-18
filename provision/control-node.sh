#!/bin/bash

set -euo pipefail

# Account Ansible and SSH will use on every VM.
readonly SSH_USER="vagrant"
readonly SSH_PASSWORD="vagrant"

# Store the control node's SSH key in vagrant's home directory.
readonly SSH_DIR="/home/${SSH_USER}/.ssh"
readonly SSH_KEY="${SSH_DIR}/id_ed25519"

# Comment this part out if you are testing the PXE server 
# Private-network addresses of the managed target nodes.
# TARGET_IPS=(
#   "192.168.56.251"
#   "192.168.56.252"
# )

echo "=== Setting up passwordless SSH from control ==="

# Install Ansible and the tools needed for first-time key copying.
apt-get update
apt-get install -y ansible sshpass openssh-client net-tools 

# enable ssh 
systemctl enable ssh

# This provisioner runs as root; give vagrant ownership of its SSH directory.
install -d -m 700 -o "${SSH_USER}" -g "${SSH_USER}" "${SSH_DIR}"

# Create a key only when one does not already exist.
if [[ ! -f "${SSH_KEY}" ]]; then
  sudo -u "${SSH_USER}" -H ssh-keygen \
    -t ed25519 \
    -f "${SSH_KEY}" \
    -N "" \
    -q
fi

# SSH requires restrictive permissions on private keys.
chown "${SSH_USER}:${SSH_USER}" "${SSH_KEY}" "${SSH_KEY}.pub"
chmod 600 "${SSH_KEY}"
chmod 644 "${SSH_KEY}.pub"

# Use the temporary Vagrant password once to install the public key remotely.
for ip in "${TARGET_IPS[@]}"; do
  echo "Copying SSH public key to ${ip}..."

  sudo -u "${SSH_USER}" -H \
    sshpass -p "${SSH_PASSWORD}" \
    ssh-copy-id \
      -i "${SSH_KEY}.pub" \
      -o StrictHostKeyChecking=no \
      "${SSH_USER}@${ip}"
done

echo "=== Passwordless SSH setup completed ==="
