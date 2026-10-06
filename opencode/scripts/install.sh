#!/usr/bin/env bash
#
# Установка веб-поиска через MCP на базе SearXNG + mcp-searxng.
# Идемпотентно: повторный запуск не ломает уже настроенную систему.
#
# Переменные окружения:
#   SEARXNG_PORT     порт SearXNG на loopback (по умолчанию 8888)
#   OPENCODE_CONFIG  путь к opencode.json (по умолчанию ~/.config/opencode/opencode.json)
#
set -euo pipefail

SEARXNG_PORT="${SEARXNG_PORT:-8888}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # каталог рецепта: opencode/
REPO_ROOT="$(cd "$RECIPE_DIR/.." && pwd)"
SEARXNG_DIR="$REPO_ROOT/searxng"
SETTINGS="$SEARXNG_DIR/config/settings.yml"
SETTINGS_EXAMPLE="$SEARXNG_DIR/config/settings.yml.example"

if [ -t 1 ]; then
  C_OK=$'\033[1;32m'; C_INFO=$'\033[1;34m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_INFO=''; C_WARN=''; C_ERR=''; C_OFF=''
fi
say()  { printf '%s==>%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

# --- 1. Проверка зависимостей -------------------------------------------------
say "Проверяю зависимости"
command -v docker >/dev/null 2>&1 || die "docker не найден"
docker compose version >/dev/null 2>&1 || die "docker compose v2 не найден"
command -v node >/dev/null 2>&1 || die "node не найден (нужен Node.js >= 22)"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 22 ] || die "нужен Node.js >= 22, найден $(node --version)"
command -v npx >/dev/null 2>&1 || die "npx не найден"
command -v python3 >/dev/null 2>&1 || die "python3 не найден (нужен для правки opencode.json)"
[ -f "$SETTINGS_EXAMPLE" ] || die "не найден $SETTINGS_EXAMPLE"
[ -f "$SEARXNG_DIR/docker-compose.yml" ] || die "не найден $SEARXNG_DIR/docker-compose.yml"
ok "docker, docker compose, node $(node --version), python3"

# --- 2. secret_key ------------------------------------------------------------
if [ ! -f "$SETTINGS" ]; then
  cp "$SETTINGS_EXAMPLE" "$SETTINGS"
  ok "создан $SETTINGS из settings.yml.example"
fi

if grep -q 'CHANGE_ME_GENERATED_BY_INSTALL_SH' "$SETTINGS"; then
  if command -v openssl >/dev/null 2>&1; then
    SECRET_KEY="$(openssl rand -hex 32)"
  else
    SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  fi
  python3 - "$SETTINGS" "$SECRET_KEY" <<'PY'
import sys
path, key = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    text = f.read()
with open(path, "w", encoding="utf-8") as f:
    f.write(text.replace("CHANGE_ME_GENERATED_BY_INSTALL_SH", key))
PY
  # 644, а не 600: контейнер стартует с cap_drop ALL и без CAP_DAC_OVERRIDE,
  # поэтому root внутри не может обойти права файла (см. compose-файл).
  chmod 644 "$SETTINGS" 2>/dev/null || true
  ok "secret_key сгенерирован в $SETTINGS"
else
  ok "secret_key уже задан — оставляю как есть"
fi

# --- 3. Запуск SearXNG --------------------------------------------------------
say "Запускаю контейнер searxng (127.0.0.1:${SEARXNG_PORT})"
SEARXNG_PORT="$SEARXNG_PORT" SEARXNG_BASE_URL="http://127.0.0.1:${SEARXNG_PORT}/" \
  docker compose -f "$SEARXNG_DIR/docker-compose.yml" up -d

say "Жду готовности JSON API (до 60 секунд)"
READY=0
for _ in $(seq 1 30); do
  if curl -fsS -m 3 "http://127.0.0.1:${SEARXNG_PORT}/search?q=test&format=json" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done
if [ "$READY" -ne 1 ]; then
  die "SearXNG не отдаёт JSON API. Проверь: docker logs searxng"
fi
ok "SearXNG отвечает: http://127.0.0.1:${SEARXNG_PORT}/search?q=test&format=json"

# --- 4. Прогрев npx-кэша ------------------------------------------------------
say "Прогреваю npx-кэш mcp-searxng (первый запуск может занять до минуты)"
if timeout 120 npx -y mcp-searxng --version >/dev/null 2>&1; then
  ok "mcp-searxng доступен через npx"
else
  warn "не удалось проверить 'npx -y mcp-searxng --version' — проверь сеть/npm"
fi

# --- 5. Прописать MCP в opencode.json ----------------------------------------
say "Настраиваю $OPENCODE_CONFIG"
mkdir -p "$(dirname "$OPENCODE_CONFIG")"
[ -f "$OPENCODE_CONFIG" ] || printf '{}\n' > "$OPENCODE_CONFIG"
BACKUP="${OPENCODE_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
cp "$OPENCODE_CONFIG" "$BACKUP"

if ! python3 - "$OPENCODE_CONFIG" "$SEARXNG_PORT" <<'PY'
import json
import sys

path, port = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)

cfg.setdefault("mcp", {})["searxng"] = {
    "type": "local",
    "command": ["npx", "-y", "mcp-searxng"],
    "environment": {"SEARXNG_URL": f"http://127.0.0.1:{port}"},
    "enabled": True,
}
cfg.setdefault("tools", {})["websearch"] = False

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
then
  cp "$BACKUP" "$OPENCODE_CONFIG"
  die "$OPENCODE_CONFIG не является строгим JSON. Пропиши блок mcp.searxng вручную (см. opencode/README.ru.md)."
fi
ok "MCP 'searxng' включён, штатный websearch отключён (бэкап: $BACKUP)"

# --- 6. Итог ------------------------------------------------------------------
echo
ok "Готово"
cat <<EOF

  SearXNG:   http://127.0.0.1:${SEARXNG_PORT}
  MCP:       npx -y mcp-searxng (SEARXNG_URL=http://127.0.0.1:${SEARXNG_PORT})
  opencode:  tools.websearch=false, инструменты searxng_* доступны

  Проверка:  bash "$RECIPE_DIR/scripts/verify.sh"
  Инструкция: $RECIPE_DIR/README.ru.md (EN: $RECIPE_DIR/README.md)
EOF
