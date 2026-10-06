#!/usr/bin/env bash
set -euo pipefail
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$RECIPE_DIR/.." && pwd)"
SEARXNG_PORT="${SEARXNG_PORT:-8888}"
docker info >/dev/null
[ -n "$(docker ps -q -f name=^searxng$ -f status=running)" ] || {
  echo '[FAIL] SearXNG container is not running' >&2; exit 1;
}
printf '[ok] SearXNG container is running\n'
# Validate JSON rather than accepting an HTML page with HTTP 200.
curl -fsS --max-time 30 "http://127.0.0.1:${SEARXNG_PORT}/search?q=SearXNG&format=json" |
  python3 -c 'import json,sys; data=json.load(sys.stdin); assert isinstance(data.get("results"), list), "Missing results array"; print("[ok] SearXNG JSON API")'
python3 "$RECIPE_DIR/scripts/verify_mcp.py" --expected-url "http://127.0.0.1:${SEARXNG_PORT}"
