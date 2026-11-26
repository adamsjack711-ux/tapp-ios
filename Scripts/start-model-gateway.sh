#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
token_file="${1:-$HOME/Library/Application Support/PocketAgent/model-gateway.key}"
gateway_config="${2:-$project_root/DeveloperTools/ModelGateway/Caddyfile}"
if [[ ! -f "$token_file" ]]; then
    echo "Missing private gateway key. Generate 32 random bytes as hex in a mode-600 file outside the project." >&2
    exit 1
fi
POCKET_AGENT_TOKEN="$(<"$token_file")"
if [[ ! "$POCKET_AGENT_TOKEN" =~ ^[a-f0-9]{64}$ ]]; then
    echo "The gateway key must be 64 lowercase hexadecimal characters." >&2
    exit 1
fi
export POCKET_AGENT_TOKEN
command -v caddy >/dev/null || { echo "Install Caddy with Homebrew first." >&2; exit 1; }
caddy validate --config "$gateway_config" --adapter caddyfile
exec caddy run --config "$gateway_config" --adapter caddyfile
