# Веб-поиск через MCP: SearXNG + mcp-searxng + Codex

[English version](README.md)

Рецепт запускает общий стек SearXNG и подключает поиск и чтение страниц к Codex
CLI через stdio. Проверено на Linux с Codex CLI **0.160.1**, MCP-сервером **2.5.1**
и SearXNG **2026.10.4-d48c4b555** (2026-10-06). Для Docker-варианта проверены
`initialize`, `tools/list` и настоящий поисковый вызов `tools/call`.

```text
Codex → stdio → docker run -i mcp-searxng → HTTP → SearXNG → поисковые движки
```

## 1. Установка и проверка

Требования: Linux, Docker с Compose v2 или новее и доступом к Docker daemon,
Codex CLI, Python >= 3.11, `curl`, интернет для скачивания образов и поиска.
Основной вариант использует Docker; Node.js на хосте не нужен.
Запускайте от своего пользователя Codex с доступом к Docker. `sudo` для всего
установщика настроит Codex пользователя root.

Из корня репозитория:

```bash
bash codex/scripts/install.sh
bash codex/scripts/verify.sh
```

Установщик создаёт `searxng/config/settings.yml`, при необходимости генерирует
секрет, запускает общий контейнер, ждёт ответа JSON API, сохраняет бэкап
конфигурации Codex и регистрирует глобальный MCP-сервер `searxng` через
`codex mcp add`. Если сервер с таким именем уже есть, его настройка заменяется.
Остальные настройки и MCP-серверы сохраняются. Повторный запуск использует
существующий ключ и контейнер. Итоговая проверка требует выдачу со ссылками.

MCP-образ закреплён по digest: повторная установка использует тот же артефакт.
SearXNG использует тег `latest` из общего Compose-файла. Обновление компонентов
описано в разделе обслуживания.

Перезапустите сессию Codex. Откройте `/mcp`, затем попросите: «Используй MCP-сервер
searxng: найди инструкцию по установке SearXNG и укажи ссылки на источники».
Добавьте правила из [AGENTS.md.example](AGENTS.md.example) в `AGENTS.md` проекта
или глобальный `~/.codex/AGENTS.md`, чтобы агент предпочитал MCP-поиск.
Установщик правила агента не изменяет.

## 2. Конфигурация

Codex хранит настройку в `${CODEX_HOME:-~/.codex}/config.toml`; CLI и расширение IDE
используют общую конфигурацию. Для ручной установки добавьте таблицы из
[config.toml.example](config.toml.example), сохранив остальные настройки файла.
Пример включает увеличенные таймауты для медленных машин. Установщик использует
стандартные таймауты Codex и заранее скачивает MCP-образ.

Эквивалент регистрации после запуска SearXNG:

```bash
docker pull isokoliuk/mcp-searxng@sha256:47c2c520c06b396b89d34bda8a4cd5961e04e4d35c59b931f63d617be45245b5
codex mcp add searxng --env SEARXNG_URL=http://127.0.0.1:8888 --env MCP_HTTP_PORT= -- \
  docker run --rm -i --network host -e SEARXNG_URL -e MCP_HTTP_PORT= \
  isokoliuk/mcp-searxng@sha256:47c2c520c06b396b89d34bda8a4cd5961e04e4d35c59b931f63d617be45245b5
codex mcp get searxng --json
codex mcp list
```

`-i` оставляет stdin открытым для MCP. Не добавляйте `-t`: TTY нарушает stdio.
`--network host` позволяет MCP-контейнеру обращаться к loopback Linux-хоста.
Docker должен работать на той же машине, что и Codex: у удалённого Docker daemon
другой loopback, этот рецепт без изменения сети не подойдёт.
`MCP_HTTP_PORT` очищается, чтобы MCP работал в режиме stdio.
HTTP-адрес SearXNG **не является** MCP endpoint: не передавайте
`http://127.0.0.1:8888` в `codex mcp add --url`.

`codex mcp list` показывает регистрацию, но не проверяет подключение или вызов
инструмента. Скрипт проверки запускает команду из конфигурации Codex, выполняет
MCP handshake, проверяет четыре инструмента и делает реальный поиск.
LLM и сторонние Python-пакеты для этого не нужны. Проверочный MCP-процесс
завершается после проверки. При обычной работе Codex запускает MCP для каждой
сессии; отдельный MCP-демон не требуется.

| MCP-инструмент | Назначение |
|---|---|
| `searxng_web_search` | Поиск с фильтрами языка, движка и времени |
| `web_url_read` | Чтение страницы или PDF |
| `searxng_search_suggestions` | Подсказки запросов |
| `searxng_instance_info` | Доступные движки и категории |

Codex может отображать инструменты с префиксом сервера; актуальные имена смотрите
в `/mcp`.

## 3. Параметры и запуск через npx

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `SEARXNG_PORT` | `8888` | Порт общего SearXNG; задайте также при проверке |
| `MCP_LAUNCHER` | `docker` | `docker` или `npx` |
| `MCP_IMAGE` | Digest из примера | Docker-образ MCP |
| `MCP_PACKAGE` | `mcp-searxng@2.5.1` | Версия npm-пакета |
| `CODEX_HOME` | `~/.codex` | Каталог конфигурации Codex |

```bash
SEARXNG_PORT=8889 bash codex/scripts/install.sh
SEARXNG_PORT=8889 bash codex/scripts/verify.sh
```

Смена порта перемещает **общий** контейнер. Обновите адрес в настройках других
агентов, которые его используют.

Если на хосте есть Node.js >= 22, npm и npx (также вариант для macOS/Docker Desktop):

```bash
MCP_LAUNCHER=npx bash codex/scripts/install.sh
```

Установщик прогреет npm-кэш, сохранит абсолютный путь к npx и зарегистрирует команду:

```bash
codex mcp add searxng --env SEARXNG_URL=http://127.0.0.1:8888 --env MCP_HTTP_PORT= -- \
  npx -y mcp-searxng@2.5.1
```

При ручной настройке TOML замените `command` на `"npx"`, а `args` на
`["-y", "mcp-searxng@2.5.1"]`, оставив таблицу окружения и таймауты.
После изменения перезапустите Codex. Проверка использует сохранённую команду и
работает с обоими вариантами. На desktop-платформах рецепт не проверялся.

Настройка встроенного поиска Codex остаётся прежней. Чтобы использовать только
MCP-поиск в отдельной сессии, запустите `codex -c 'web_search="disabled"'`.
Для глобальной настройки добавьте `web_search = "disabled"` **на верхнем уровне**
`config.toml`. Правила агента помогают выбрать MCP-инструменты.

## 4. Диагностика и обслуживание

| Симптом | Действие |
|---|---|
| Docker permission denied | Дайте своему пользователю доступ к daemon; не настраивайте Codex от root |
| В текущей сессии нет MCP | Перезапустите Codex, откройте `/mcp`, проверьте `codex mcp get searxng --json` |
| Таймаут инициализации | Заранее скачайте образ/пакет; задайте `startup_timeout_sec = 30` в таблице MCP |
| JSON API отвечает 403/429 | Проверьте `json` в `search.formats` и `server.limiter: false`, перезапустите SearXNG |
| Поиск без результатов | Проверьте `docker logs --tail 50 searxng`, смените запрос/движок. Капча или лимит на одном движке не мешают другим выдавать результаты |
| Порт занят | Задайте `SEARXNG_PORT` и для установки, и для проверки |
| Нельзя редактировать settings после запуска | Контейнер может передать каталог uid 977; редактируйте с подходящими правами. Оставьте режим 644 для capabilities из Compose |
| Codex работает удалённо или в другом контейнере | `127.0.0.1` относится к его окружению; запустите стек там или явно настройте доступную сеть |

```bash
docker logs --tail 50 searxng
docker compose -f searxng/docker-compose.yml restart searxng
# Обновить общий SearXNG:
docker compose -f searxng/docker-compose.yml pull
docker compose -f searxng/docker-compose.yml up -d
# Обновить MCP, зарегистрировать новый образ и повторить поисковую проверку:
MCP_IMAGE=isokoliuk/mcp-searxng:latest bash codex/scripts/install.sh
# Удалить регистрацию в Codex (общий SearXNG продолжает работать):
codex mcp remove searxng
```

SearXNG слушает только `127.0.0.1`, публичный MCP-порт не открывается.
Сгенерированный конфиг содержит секрет и исключён из git. Отключённый limiter
предназначен только для этого локального развёртывания. Поисковые запросы идут
к внешним движкам, чтение страниц напрямую обращается к внешним сайтам.

## Источники

- [Официальная документация OpenAI: Codex MCP](https://developers.openai.com/codex/mcp/)
- [Справочник конфигурации Codex](https://developers.openai.com/codex/config-reference/)
- [mcp-searxng](https://github.com/ihor-sokoliuk/mcp-searxng)
- [Документация SearXNG](https://docs.searxng.org)
