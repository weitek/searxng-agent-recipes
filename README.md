# searxng-agent-recipes

**Private keyless web search for AI coding agents via SearXNG + mcp-searxng.**

[Русская версия](README.ru.md)

Coding agents are far more useful when they can check facts: docs, versions, licenses,
release notes. Cloud search MCP servers require API keys and paid plans, and a coding
CLI's built-in search may be vendor-locked or simply unavailable. These recipes wire a
self-hosted [SearXNG](https://docs.searxng.org) instance into an agent via
[mcp-searxng](https://github.com/ihor-sokoliuk/mcp-searxng) — no keys, no subscriptions,
loopback only.

```
agent CLI  ──stdio──▶  npx mcp-searxng  ──HTTP──▶  SearXNG (Docker, 127.0.0.1:8888)  ──▶  Google/Bing/DDG/Wikipedia/…
 MCP client              MCP server                  metasearch engine                    engines
```

- **Self-hosted** — SearXNG runs in Docker and binds to `127.0.0.1`; nothing is exposed.
- **Keyless** — no Google/Bing/Brave/Tavily API keys, no paid plans.
- **Private** — queries stay on your machine; only SearXNG talks to the search engines.
- **MCP-native** — the agent gets search and page-reading tools over the Model Context
  Protocol and can replace its built-in web search.

## Recipes

| Agent | Status | Docs |
|---|---|---|
| opencode v1 | Tested (1.18.34) | [opencode/README.md](opencode/README.md) |
| opencode v2 | Planned | — |
| Codex CLI | Tested (0.160.1, Linux/Docker) | [codex/README.md](codex/README.md) |
| Claude Code | Planned | — |
| Grok | Planned | — |

## Repository layout

```
.
├── searxng/                 # shared SearXNG stack: Docker Compose + settings template
│   ├── docker-compose.yml
│   └── config/
│       └── settings.yml.example
├── opencode/                # opencode recipe
│   ├── README.md            # this recipe in English
│   ├── README.ru.md         # на русском
│   └── scripts/
│       ├── install.sh       # deploy SearXNG + wire MCP into opencode
│       └── verify.sh        # check the whole stack
└── codex/                   # Codex CLI recipe
    ├── README.md
    ├── README.ru.md
    ├── config.toml.example
    ├── AGENTS.md.example
    └── scripts/
        ├── install.sh
        ├── verify.sh
        └── verify_mcp.py
```

The `searxng/` stack is client-agnostic: opencode and Codex share the same container.
Future Claude Code and Grok recipes can reuse it too. The real
`searxng/config/settings.yml` is created by
the installer from `settings.yml.example` and is gitignored because it contains the
instance `secret_key`.

## Quick start (opencode)

Requirements: Docker + Compose v2, Node.js >= 22, `python3`, `curl`, and opencode 1.x
installed.

```bash
git clone https://github.com/weitek/searxng-agent-recipes.git
cd searxng-agent-recipes
bash opencode/scripts/install.sh   # deploy SearXNG, generate the key, wire the MCP server
bash opencode/scripts/verify.sh    # check the whole stack
```

Then add the agent rule from
[§5 of the recipe](opencode/README.md#5-agent-rules-agentsmd) to your `AGENTS.md` and
restart opencode. The recipe's built-in `websearch` is disabled in favor of the
`searxng_*` MCP tools.

## Quick start (Codex)

Requirements: Linux, Docker + Compose v2 or newer, Codex CLI, Python >= 3.11 and `curl`.
The MCP server runs in Docker; host Node.js is unnecessary.

```bash
bash codex/scripts/install.sh
bash codex/scripts/verify.sh
```

Restart Codex and open `/mcp`. Manual configuration, the npx alternative and agent
rules are in the [Codex recipe](codex/README.md). Verification performs a real MCP
search and requires source URLs in the results.

## Security

- SearXNG binds to loopback (`127.0.0.1`) only.
- `secret_key` is generated locally and never committed (`settings.yml` is gitignored).
- `limiter: false` is only safe for loopback; do not expose the instance publicly
  without reading the SearXNG hardening docs.

## License

[MIT](LICENSE)
