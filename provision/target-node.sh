#!/bin/bash

# option to fail fast 
set -euo pipefail

apt update
apt install -y openssh-server net-tools
    
# Set vagrant password to vagrant (ensure it's set)
echo 'vagrant:vagrant' | chpasswd

# Create SSH override configuration
cat > /etc/ssh/sshd_config.d/vagrant.conf <<EOF
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
EOF

mkdir -p /run/sshd
chmod 755 /run/sshd
sudo sshd -t 
# Restart sshd to pick up the change
systemctl restart sshd || service ssh restart

sleep 5

# Check SSH status
systemctl status ssh