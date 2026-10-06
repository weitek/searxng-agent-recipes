# searxng-agent-recipes

**Private keyless web search for AI coding agents via SearXNG + mcp-searxng.**

(Приватный веб-поиск для AI-агентов через SearXNG + mcp-searxng — без API-ключей.)

[English version](README.md)

Агенты заметно полезнее, когда могут проверять факты: документацию, версии, лицензии,
release notes. Облачные MCP-серверы поиска требуют API-ключей и платных подписок, а
встроенный поиск coding-агента может быть вендор-локнутым или просто недоступным.
Эти рецепты подключают self-hosted [SearXNG](https://docs.searxng.org) к агенту через
[mcp-searxng](https://github.com/ihor-sokoliuk/mcp-searxng) — без ключей, без подписок,
только loopback.

```
agent CLI  ──stdio──▶  npx mcp-searxng  ──HTTP──▶  SearXNG (Docker, 127.0.0.1:8888)  ──▶  Google/Bing/DDG/Wikipedia/…
 MCP-клиент             MCP-сервер                     метапоисковик                        движки
```

- **Self-hosted** — SearXNG работает в Docker и слушает только `127.0.0.1`; наружу
  ничего не выставлено.
- **Без ключей** — не нужны API-ключи Google/Bing/Brave/Tavily и платные тарифы.
- **Приватно** — запросы остаются на вашей машине; с поисковиками общается только SearXNG.
- **MCP-native** — агент получает инструменты поиска и чтения страниц по Model Context
  Protocol и может заменить ими встроенный веб-поиск.

## Рецепты

| Агент | Статус | Документация |
|---|---|---|
| opencode v1 | Проверено (1.18.34) | [opencode/README.ru.md](opencode/README.ru.md) |
| opencode v2 | В планах | — |
| Codex CLI | Проверено (0.160.1, Linux/Docker) | [codex/README.ru.md](codex/README.ru.md) |
| Claude Code | В планах | — |
| Grok | В планах | — |

## Структура репозитория

```
.
├── searxng/                 # общий стек SearXNG: Docker Compose + шаблон настроек
│   ├── docker-compose.yml
│   └── config/
│       └── settings.yml.example
├── opencode/                # рецепт для opencode
│   ├── README.md            # English version
│   ├── README.ru.md         # этот рецепт на русском
│   └── scripts/
│       ├── install.sh       # развернуть SearXNG + прописать MCP в opencode
│       └── verify.sh        # проверить весь стек
└── codex/                   # рецепт для Codex CLI
    ├── README.md
    ├── README.ru.md
    ├── config.toml.example
    ├── AGENTS.md.example
    └── scripts/
        ├── install.sh
        ├── verify.sh
        └── verify_mcp.py
```

Стек `searxng/` не привязан к клиенту: opencode и Codex используют общий контейнер.
Будущие рецепты Claude Code и Grok смогут переиспользовать его. Рабочий
`searxng/config/settings.yml` создаётся установщиком из `settings.yml.example` и
находится в `.gitignore`, так как содержит `secret_key` инстанса.

## Быстрый старт (opencode)

Требования: Docker + Compose v2, Node.js >= 22, `python3`, `curl` и установленный
opencode 1.x.

```bash
git clone https://github.com/weitek/searxng-agent-recipes.git
cd searxng-agent-recipes
bash opencode/scripts/install.sh   # развернуть SearXNG, сгенерировать ключ, прописать MCP
bash opencode/scripts/verify.sh    # проверить весь стек
```

Затем добавьте правило для агента из
[§5 рецепта](opencode/README.ru.md#5-правила-для-агента-agentsmd) в свой `AGENTS.md`
и перезапустите opencode. Встроенный `websearch` отключается в пользу MCP-инструментов
`searxng_*`.

## Быстрый старт (Codex)

Требования: Linux, Docker + Compose v2 или новее, Codex CLI, Python >= 3.11 и `curl`.
MCP работает в Docker, Node.js на хосте не нужен.

```bash
bash codex/scripts/install.sh
bash codex/scripts/verify.sh
```

Перезапустите Codex и откройте `/mcp`. Ручная настройка, вариант с npx и правила
агента: [рецепт для Codex](codex/README.ru.md). Проверка выполняет реальный поиск
через MCP и требует ссылки в выдаче.

## Безопасность

- SearXNG слушает только loopback (`127.0.0.1`).
- `secret_key` генерируется локально и не попадает в git (`settings.yml` в `.gitignore`).
- `limiter: false` безопасен только для loopback; не выставляйте инстанс публично,
  не прочитав рекомендации SearXNG по защите.

## Лицензия

[MIT](LICENSE)
