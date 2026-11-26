#!/bin/bash
set -euo pipefail
gateway_url="${1:?Pass the private HTTPS base URL without /v1.}"
token_file="${2:-$HOME/Library/Application Support/PocketAgent/model-gateway.key}"
[[ "$gateway_url" == https://* ]] || { echo "An HTTPS URL is required." >&2; exit 1; }
gateway_token="$(<"$token_file")"
[[ "$gateway_token" =~ ^[a-f0-9]{64}$ ]] || { echo "Invalid key file." >&2; exit 1; }
route_args=()
# Optional approved LAN route; curl still validates the URL's DNS identity.
if [[ -n "${POCKET_GATEWAY_CONNECT_TO:-}" ]]; then
    route_args=(--connect-to "$POCKET_GATEWAY_CONNECT_TO")
fi

check() {
    local expected="$1" method="$2" path="$3" key="$4" actual
    # Feed the secret through stdin, never a command-line argument or log.
    actual="$(printf 'header = "Authorization: Bearer %s"\n' "$key" |
        curl --config - "${route_args[@]}" --silent --show-error --max-time 20 --request "$method" \
        --output /dev/null --write-out '%{http_code}' "${gateway_url%/}$path")"
    [[ "$actual" == "$expected" ]] || {
        echo "FAIL $method $path: expected $expected, got $actual" >&2
        exit 1
    }
    echo "PASS $method $path: $actual"
}

check 403 GET /v1/models ''
check 403 GET /v1/models invalid
check 200 GET /v1/models "$gateway_token"
check 403 POST /v1/chat/completions ''
check 403 GET /v1/chat/completions "$gateway_token"
check 403 GET /api/tags "$gateway_token"
check 403 POST /api/pull "$gateway_token"
check 403 DELETE /api/delete "$gateway_token"
check 403 GET / "$gateway_token"
