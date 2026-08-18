#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl jq

# installing ollama 
curl -fsSL https://ollama.com/install.sh | sh

# Configure Ollama to listen on the private network. A systemd drop-in keeps
# this setting after VM reboots.
install -d -m 0755 /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# Pull the models
sudo -u ollama ollama pull llama3.2:3b
sudo -u ollama ollama pull nomic-embed-text

# Allow API access only from the Vagrant private network.
if command -v ufw &> /dev/null; then
    ufw allow from 192.168.56.0/24 to any port 11434 proto tcp
fi

echo "Done"