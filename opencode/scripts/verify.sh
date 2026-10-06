#!/usr/bin/env bash
#
# Проверка работоспособности веб-поиска через MCP (SearXNG + mcp-searxng + opencode).
# Возвращает 0, если все проверки пройдены, и 1, если есть ошибки.
#
# Переменные окружения:
#   SEARXNG_PORT     порт SearXNG на loopback (по умолчанию 8888)
#   OPENCODE_CONFIG  путь к opencode.json (по умолчанию ~/.config/opencode/opencode.json)
#
set -uo pipefail

SEARXNG_PORT="${SEARXNG_PORT:-8888}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # каталог рецепта: opencode/
REPO_ROOT="$(cd "$RECIPE_DIR/.." && pwd)"
URL="http://127.0.0.1:${SEARXNG_PORT}"
FAILS=0

if [ -t 1 ]; then
  C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_ERR=''; C_OFF=''
fi
pass() { printf '  %s[ok]%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
fail() { printf '  %s[FAIL]%s %s\n' "$C_ERR" "$C_OFF" "$*"; FAILS=$((FAILS + 1)); }

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name"
  fi
}

echo "Проверка MCP-поиска (SearXNG + mcp-searxng + opencode)"

# 1. Docker и контейнер
check "docker доступен" docker info
if [ -n "$(docker ps -q -f name=^searxng$ -f status=running 2>/dev/null)" ]; then
  pass "контейнер searxng запущен"
else
  fail "контейнер searxng не запущен (docker compose -f \"$REPO_ROOT/searxng/docker-compose.yml\" up -d)"
fi

# 2. JSON API SearXNG
if curl -fsS -m 5 "${URL}/search?q=test&format=json" 2>/dev/null | grep -q '"results"'; then
  pass "JSON API отвечает: ${URL}/search?q=test&format=json"
else
  fail "JSON API не отвечает (проверь limiter: false и formats: [html, json] в settings.yml)"
fi

# 3. Node.js >= 22
if command -v node >/dev/null 2>&1 && [ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]; then
  pass "Node.js $(node --version)"
else
  fail "нет Node.js >= 22 (нужен для npx mcp-searxng)"
fi

# 4. mcp-searxng через npx
if timeout 60 npx -y mcp-searxng --version >/dev/null 2>&1; then
  pass "mcp-searxng запускается через npx"
else
  fail "npx -y mcp-searxng не запускается (проверь npm/сеть)"
fi

# 5. Конфиг opencode
if [ -f "$OPENCODE_CONFIG" ]; then
  if python3 - "$OPENCODE_CONFIG" "$SEARXNG_PORT" <<'PY' >/dev/null 2>&1
import json
import sys

path, port = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)

server = cfg.get("mcp", {}).get("searxng", {})
assert server.get("enabled") is True, "mcp.searxng disabled"
assert server.get("environment", {}).get("SEARXNG_URL") == f"http://127.0.0.1:{port}", "SEARXNG_URL mismatch"
assert cfg.get("tools", {}).get("websearch") is False, "tools.websearch not disabled"
PY
  then
    pass "opencode.json: mcp.searxng включён, SEARXNG_URL=${URL}, websearch отключён"
  else
    fail "opencode.json настроен не полностью (см. opencode/README.ru.md, разделы 2-3)"
  fi
else
  fail "нет файла $OPENCODE_CONFIG"
fi

# 6. opencode видит MCP-сервер
if command -v opencode >/dev/null 2>&1; then
  MCP_OUT="$(timeout 30 opencode mcp list 2>&1 | sed -e 's/\x1b\[[0-9;]*m//g')"
  if printf '%s' "$MCP_OUT" | grep -q 'searxng' && printf '%s' "$MCP_OUT" | grep -q 'connected'; then
    pass "opencode mcp list: searxng connected"
  else
    fail "opencode mcp list не подтверждает подключение searxng:"
    printf '%s\n' "$MCP_OUT" | sed 's/^/       /'
  fi
else
  fail "opencode не найден в PATH"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  printf '%sВсе проверки пройдены.%s В сессии opencode спроси: «найди в интернете ...»\n' "$C_OK" "$C_OFF"
  exit 0
else
  printf '%sПровалено проверок: %d.%s Смотри раздел «Диагностика» в opencode/README.ru.md\n' "$C_ERR" "$FAILS" "$C_OFF"
  exit 1
fi
