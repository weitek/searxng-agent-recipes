# MCP-поиск в интернете: SearXNG + mcp-searxng + opencode

[English version](README.md)

Рецепт для **opencode v1** (проверено на 1.18.34). Также доступен [рецепт Codex](../codex/README.ru.md). Поддержка opencode v2,
Claude Code и Grok — в планах, см. [корневой README](../README.ru.md).

Инструкция описывает, как поднять self-hosted веб-поиск для AI-агента и заменить им
штатный инструмент `websearch` в opencode.

```
opencode  ──stdio──▶  npx mcp-searxng  ──HTTP──▶  SearXNG (Docker, 127.0.0.1:8888)  ──▶  Google/Bing/DDG/Wikipedia/…
   MCP-клиент             MCP-сервер                    метапоисковик                        движки
```

Почему так: SearXNG не требует API-ключей и платных подписок, работает только на
loopback, запросы не уходят вендору поиска целиком. MCP-сервер `mcp-searxng`
([ihor-sokoliuk/mcp-searxng](https://github.com/ihor-sokoliuk/mcp-searxng))
даёт агенту инструменты поиска и чтения страниц.

---

## 0. Быстрая проверка (TL;DR)

На уже настроенной машине:

```bash
curl -s 'http://127.0.0.1:8888/search?q=test&format=json' | head -c 200   # JSON с results
opencode mcp list                                                          # searxng connected
```

Проверка всего стека одной командой:

```bash
bash opencode/scripts/verify.sh
```

Установка с нуля (на новом сервере, из корня клонированного репозитория):

```bash
bash opencode/scripts/install.sh
```

---

## 1. Что получится в итоге

| Компонент | Где / что |
|---|---|
| SearXNG | Docker-контейнер `searxng`, `searxng/searxng:latest`, `127.0.0.1:8888 -> 8080` |
| Compose-проект | `searxng/docker-compose.yml` |
| Конфиг SearXNG | `searxng/config/settings.yml` (`limiter: false`, `formats: [html, json]`; создаётся установщиком из `settings.yml.example`) |
| MCP-сервер | `npx -y mcp-searxng` (v2.5.0), `SEARXNG_URL=http://127.0.0.1:8888` |
| opencode | 1.18.34, конфиг `~/.config/opencode/opencode.json` |
| Штатный поиск | отключён: `"tools": {"websearch": false}` |

Инструменты, которые видит агент:

| Инструмент | Назначение |
|---|---|
| `searxng_searxng_web_search` | поиск (`query`, `pageno`, `language`, `time_range`, `engines`, `num_results`, …) |
| `searxng_web_url_read` | чтение страницы или PDF по URL |
| `searxng_searxng_search_suggestions` | автодополнение/уточнение запроса |
| `searxng_searxng_instance_info` | список движков и категорий SearXNG |

Обслуживание:

```bash
docker logs --tail 50 searxng                        # логи SearXNG
docker compose -f searxng/docker-compose.yml restart
docker compose -f searxng/docker-compose.yml pull && \
docker compose -f searxng/docker-compose.yml up -d   # обновление образа
```

Отдельные процессы `npm exec mcp-searxng` в `ps aux` — это норма: opencode
запускает свой stdio-процесс на каждую сессию.

---

## 2. Развёртывание SearXNG с нуля

### Требования

- Docker + `docker compose` v2
- Node.js **>= 22** и `npx` (для `mcp-searxng`)
- `python3` (правит `opencode.json`), `curl`, `openssl` (или python3) для генерации ключа

### Файлы

`searxng/docker-compose.yml` — SearXNG слушает только loopback, порт задаётся
переменной `SEARXNG_PORT` (по умолчанию 8888):

```yaml
services:
  searxng:
    image: docker.io/searxng/searxng:latest
    container_name: searxng
    restart: unless-stopped
    ports:
      - "127.0.0.1:${SEARXNG_PORT:-8888}:8080"
    volumes:
      - ./config:/etc/searxng:rw
    environment:
      - SEARXNG_BASE_URL=${SEARXNG_BASE_URL:-http://127.0.0.1:8888/}
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
    logging:
      driver: "json-file"
      options:
        max-size: "1m"
        max-file: "2"
```

`searxng/config/settings.yml` — обязательны `limiter: false` и JSON в `search.formats`,
иначе MCP получит 403/429:

```yaml
use_default_settings: true

general:
  instance_name: "MCP Search"
  donation_url: false
  contact_url: false

server:
  secret_key: "CHANGE_ME_GENERATED_BY_INSTALL_SH"   # заменить: openssl rand -hex 32
  limiter: false
  public_instance: false
  image_proxy: false

search:
  formats:
    - html
    - json
  safe_search: 0
  autocomplete: ""
```

### Запуск вручную

```bash
cd searxng
openssl rand -hex 32          # полученный ключ вставить в secret_key
docker compose up -d
curl -s 'http://127.0.0.1:8888/search?q=test&format=json' | head -c 200
```

Либо одной командой всё сразу (ключ, запуск, MCP, отключение штатного поиска):

```bash
bash opencode/scripts/install.sh
```

Если `searxng/config/settings.yml` ещё нет, скрипт создаст его из
`settings.yml.example` и подставит сгенерированный `secret_key`.

---

## 3. Подключение MCP к opencode

Блок в `~/.config/opencode/opencode.json` (глобально для всех проектов) или в
`opencode.json` конкретного проекта:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "searxng": {
      "type": "local",
      "command": ["npx", "-y", "mcp-searxng"],
      "environment": {
        "SEARXNG_URL": "http://127.0.0.1:8888"
      },
      "enabled": true
    }
  }
}
```

Альтернативы запуска:

- глобальная установка: `npm i -g mcp-searxng`, затем `"command": ["mcp-searxng"]` (без npx-задержки);
- Docker: `"command": ["docker", "run", "-i", "--rm", "-e", "SEARXNG_URL", "isokoliuk/mcp-searxng:latest"]`
  с `"environment": {"SEARXNG_URL": "http://127.0.0.1:8888"}` (из контейнера loopback хоста
  доступен через `host.docker.internal` в Linux не всегда — проще npx).

Важно: первый запуск `npx` скачивает пакет и может превысить таймаут инициализации
opencode (по умолчанию 5 с). Поэтому полезно прогревать кэш:

```bash
npx -y mcp-searxng --version
```

При необходимости таймаут увеличивается полем `"timeout": 20000` в блоке сервера.

Проверка подключения:

```bash
opencode mcp list        # ожидаем: ✓ searxng connected
```

После правки конфига сессию opencode нужно перезапустить.

---

## 4. Замена штатного поиска

Встроенный `websearch` в opencode включается вендорским провайдером и в этой среде
отвечает ошибкой 403. Он отключается ключом `tools`:

```json
{
  "tools": {
    "websearch": false
  }
}
```

Полный итоговый `opencode.json` (минимальный вариант):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "tools": {
    "websearch": false
  },
  "mcp": {
    "searxng": {
      "type": "local",
      "command": ["npx", "-y", "mcp-searxng"],
      "environment": {
        "SEARXNG_URL": "http://127.0.0.1:8888"
      },
      "enabled": true
    }
  }
}
```

Нюансы:

- отключается только `websearch`; `webfetch` (загрузка известного URL) остаётся и
  дополняет `searxng_web_url_read`;
- MCP можно отключать/включать точечно: `"tools": {"searxng_*": false}` — выключить
  все инструменты сервера, `"tools": {"searxng_searxng_web_search": false}` — один;
- чтобы оставить MCP только конкретному агенту: отключить глобально
  (`"tools": {"searxng*": false}`) и включить в `agent.<имя>.tools`.

---

## 5. Правила для агента (AGENTS.md)

Чтобы модель сама предпочитала MCP-поиск и не заявляла «поиск недоступен»,
добавьте сниппет в `AGENTS.md` — глобальный `~/.config/opencode/AGENTS.md`
(все проекты) или корневой `AGENTS.md` проекта:

```markdown
## Веб-поиск
- Веб-поиск доступен через MCP-сервер `searxng`: `searxng_searxng_web_search` (поиск)
  и `searxng_web_url_read` (чтение страницы или PDF).
- Для внешних проверяемых фактов (цены, тарифы, лицензии, версии, статистика) сначала
  ищи через `searxng_searxng_web_search` и указывай источник (URL). Только если факт
  не нашёлся — помечай его как «Допущение».
- Штатный инструмент `websearch` отключён (`tools.websearch = false`) — это ожидаемо.
  Не утверждай, что «внешний поиск недоступен», не вызвав `searxng_searxng_web_search`.
```

---

## 6. Скрипты

| Скрипт | Что делает |
|---|---|
| `opencode/scripts/install.sh` | проверяет docker/node/python3, создаёт `searxng/config/settings.yml` из `settings.yml.example` и генерирует `secret_key` вместо плейсхолдера, поднимает контейнер, ждёт JSON API, прогревает npx-кэш, прописывает `mcp.searxng` и `tools.websearch=false` в opencode.json (с бэкапом `*.bak-ГГГГММДД-ЧЧММСС`) |
| `opencode/scripts/verify.sh` | проверяет контейнер, JSON API, Node, `npx mcp-searxng`, конфиг opencode и `opencode mcp list`; код возврата 1 при ошибках |

SearXNG-стек (`searxng/docker-compose.yml`, `searxng/config/`) лежит в корне репозитория
и является общим для всех рецептов; скрипты opencode используют его, но не дублируют.

Переменные окружения: `SEARXNG_PORT` (по умолчанию 8888), `OPENCODE_CONFIG`
(по умолчанию `~/.config/opencode/opencode.json`).

```bash
SEARXNG_PORT=8889 bash opencode/scripts/install.sh     # нестандартный порт
bash opencode/scripts/verify.sh
```

Скрипты идемпотентны: повторный запуск не дублирует блоки и не перезаписывает
уже сгенерированный `secret_key`.

---

## 7. Диагностика

| Симптом | Причина | Решение |
|---|---|---|
| `opencode mcp list` не видит `searxng` / статус failed | MCP-процесс не стартовал (нет Node >= 22, npx не скачал пакет) | `node -v`; вручную `npx -y mcp-searxng --version`; перезапустить opencode |
| Первый вызов инструмента зависает/таймаутит | холодный npx-кэш, инициализация > 5 с | прогреть `npx -y mcp-searxng --version` или `"timeout": 20000` в блоке MCP |
| `403 Forbidden`, `format is not allowed` | в SearXNG не включён JSON | в `settings.yml`: `search.formats: [html, json]`, затем restart контейнера |
| `429 Too Many Requests` | включён `limiter` | `limiter: false` (допустимо только для loopback), restart |
| Пустая выдача | движки отдают капчу/бан, узкий запрос | `docker logs searxng`; сменить запрос/движок через `searxng_searxng_instance_info`; `safe_search: 0` |
| Ошибка `secret_key` в логах | ключ не задан | `openssl rand -hex 32` в `settings.yml`, restart |
| Порт 8888 занят | другой сервис | `SEARXNG_PORT=8889 bash opencode/scripts/install.sh` (обновит и `SEARXNG_URL`) |
| В логах `PermissionError: /etc/searxng/settings.yml` | файл недоступен процессу: контейнер стартует с `cap_drop: ALL` (без CAP_DAC_OVERRIDE), поэтому режим `600/640` не читается | `sudo chmod 644 searxng/config/settings.yml`, затем restart; не ужесточать права вручную |
| Не удаётся отредактировать `settings.yml` после первого запуска | каталог `config/` принадлежит uid 977 (пользователь searxng в контейнере) | редактировать через `sudo`, например `sudo nano searxng/config/settings.yml` |
| Агент всё равно зовёт `websearch` | правило не добавлено / сессия старая | добавить сниппет из §5, перезапустить opencode; при 403 у встроенного — он ожидаемо отключён |
| `opencode.json` не изменился после install.sh | это JSONC с комментариями (строгий JSON-парсер их не понимает) | добавить блок `mcp.searxng` вручную (§3); скрипт вернёт бэкап |
| Много процессов `mcp-searxng` | норма: процесс на каждую сессию клиента | ничего делать не нужно |

---

## 8. Безопасность и эксплуатация

- SearXNG биндится только на `127.0.0.1` — наружу порт не торчит; так и должно быть.
- `secret_key` — секрет: `searxng/config/settings.yml` создаётся установщиком из
  `settings.yml.example` и уже включён в `.gitignore` — не коммитить его. Ротация:
  заменить значение и `docker compose restart searxng`.
- После первого запуска каталог `searxng/config/` переходит во владение uid 977
  (пользователь `searxng` внутри контейнера) — правки только через `sudo`.
  Права на `settings.yml` должны оставаться `644`: при `cap_drop: ALL` контейнер
  не может обойти права файла, и режим `600/640` приведёт к ошибке запуска.
- `limiter: false` безопасен только для loopback. Если выставляете SearXNG публично,
  включайте `limiter`, `public_instance` и protections из документации SearXNG.
- Обновление: `docker compose pull && docker compose up -d`; MCP-пакет обновится
  сам, т.к. используется `npx -y mcp-searxng` (при необходимости зафиксировать версию:
  `mcp-searxng@2.5.0`).
- Логи ограничены (`max-size: 1m`, `max-file: 2`) — диск не забьют.

## Ссылки

- opencode MCP: <https://opencode.ai/docs/mcp-servers/>
- mcp-searxng: <https://github.com/ihor-sokoliuk/mcp-searxng>
- SearXNG: <https://docs.searxng.org>
