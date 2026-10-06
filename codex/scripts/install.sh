#!/usr/bin/env bash
# Linux Docker/stdio recipe; MCP_LAUNCHER=npx also supports macOS/Windows with WSL.
set -euo pipefail
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$RECIPE_DIR/.." && pwd)"
SEARXNG_PORT="${SEARXNG_PORT:-8888}"
MCP_LAUNCHER="${MCP_LAUNCHER:-docker}"
MCP_IMAGE="${MCP_IMAGE:-isokoliuk/mcp-searxng@sha256:47c2c520c06b396b89d34bda8a4cd5961e04e4d35c59b931f63d617be45245b5}"
MCP_PACKAGE="${MCP_PACKAGE:-mcp-searxng@2.5.1}"
CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
SETTINGS="$REPO_ROOT/searxng/config/settings.yml"
URL="http://127.0.0.1:${SEARXNG_PORT}"
die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
for dependency in docker codex python3 curl; do
  command -v "$dependency" >/dev/null || die "$dependency is required"
done
python3 -c 'import tomllib' || die 'Python >= 3.11 is required'
python3 - "$SEARXNG_PORT" <<'CHECK'
import sys
port = sys.argv[1]
if not port.isascii() or not port.isdecimal() or not 1 <= int(port) <= 65535:
    sys.exit('SEARXNG_PORT must be an integer between 1 and 65535')
CHECK
docker compose version >/dev/null
docker info >/dev/null
case "$MCP_LAUNCHER" in
  docker)
    [ "$(uname -s)" = Linux ] || die 'Docker launcher requires Linux host networking; use MCP_LAUNCHER=npx'
    docker pull "$MCP_IMAGE"
    MCP_COMMAND=(docker run --rm -i --network host -e SEARXNG_URL -e MCP_HTTP_PORT= "$MCP_IMAGE")
    ;;
  npx)
    command -v npx >/dev/null || die 'npx is required'
    command -v npm >/dev/null || die 'npm is required'
    command -v node >/dev/null || die 'Node.js >= 22 is required'
    [ "$(node -p 'Number(process.versions.node.split(".")[0])')" -ge 22 ] || die 'Node.js >= 22 is required'
    # Populate the package cache before Codex's shorter startup timeout.
    npm exec --yes --package="$MCP_PACKAGE" -- mcp-searxng --version
    MCP_COMMAND=("$(command -v npx)" -y "$MCP_PACKAGE")
    ;;
  *) die 'MCP_LAUNCHER must be docker or npx' ;;
esac
python3 - "$SETTINGS" <<'SETUP'
import os
from pathlib import Path
import secrets
import sys
path = Path(sys.argv[1])
text = path.read_text() if path.exists() else path.with_suffix('.yml.example').read_text()
marker = 'CHANGE_ME_GENERATED_BY_INSTALL_SH'
if not path.exists() or marker in text:
    # Do not print the key; settings.yml is gitignored.
    path.write_text(text.replace(marker, secrets.token_hex(32)))
    os.chmod(path, 0o644)  # cap_drop: ALL prevents bypassing file permissions.
SETUP
SEARXNG_PORT="$SEARXNG_PORT" SEARXNG_BASE_URL="${URL}/" \
  docker compose -f "$REPO_ROOT/searxng/docker-compose.yml" up -d
printf 'Waiting for SearXNG JSON API...\n'
python3 - "$URL" <<'READY'
import json
import sys
import time
from urllib.request import urlopen
url = sys.argv[1] + '/search?q=SearXNG&format=json'
deadline = time.monotonic() + 60
while time.monotonic() < deadline:
    try:
        with urlopen(url, timeout=5) as response:
            data = json.load(response)
        if isinstance(data.get('results'), list):
            break
    except (OSError, ValueError):
        pass
    time.sleep(2)
else:
    sys.exit('SearXNG JSON API unavailable. Check: docker logs --tail 50 searxng')
READY
mkdir -p "$CODEX_CONFIG_DIR"
if [ -f "$CODEX_CONFIG_DIR/config.toml" ]; then
  BACKUP="$CODEX_CONFIG_DIR/config.toml.bak-$(date +%Y%m%d-%H%M%S)-$$"
  cp -p "$CODEX_CONFIG_DIR/config.toml" "$BACKUP"
  printf 'Config backup: %s\n' "$BACKUP"
fi
# The Codex CLI updates only this server, preserving other user settings.
codex mcp add searxng --env "SEARXNG_URL=$URL" --env MCP_HTTP_PORT= -- "${MCP_COMMAND[@]}"
bash "$RECIPE_DIR/scripts/verify.sh"
printf '\nReady. Restart Codex and open /mcp. Agent rules: %s/AGENTS.md.example\n' "$RECIPE_DIR"
