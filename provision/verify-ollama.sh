#!/bin/bash

set -euo pipefail

for attempt in {1..30}; do
  if curl --fail --silent --show-error http://127.0.0.1:11434/api/tags; then
    echo
    echo "Ollama API health check passed."
    exit 0
  fi
  sleep 2
done

echo "Ollama API did not become ready within 60 seconds." >&2
exit 1
