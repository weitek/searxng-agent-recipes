# Web search via MCP: SearXNG + mcp-searxng + opencode

[Русская версия](README.ru.md)

Recipe for **opencode v1** (tested on 1.18.34). Support for opencode v2, Codex,
Claude Code and Grok is planned — see the [root README](../README.md).

This guide shows how to stand up self-hosted web search for an AI agent and replace
opencode's built-in `websearch` tool with it.

```
opencode  ──stdio──▶  npx mcp-searxng  ──HTTP──▶  SearXNG (Docker, 127.0.0.1:8888)  ──▶  Google/Bing/DDG/Wikipedia/…
   MCP client             MCP server                    metasearch engine                 engines
```

Why this way: SearXNG requires no API keys or paid subscriptions, listens on loopback
only, and queries are not handed wholesale to a search vendor. The `mcp-searxng` MCP
server ([ihor-sokoliuk/mcp-searxng](https://github.com/ihor-sokoliuk/mcp-searxng))
gives the agent search and page-reading tools.

---

## 0. Quick check (TL;DR)

On an already configured machine:

```bash
curl -s 'http://127.0.0.1:8888/search?q=test&format=json' | head -c 200   # JSON with results
opencode mcp list                                                          # searxng connected
```

Check the whole stack with one command:

```bash
bash opencode/scripts/verify.sh
```

Install from scratch (on a new server, from the repository root):

```bash
bash opencode/scripts/install.sh
```

---

## 1. What you get

| Component | Where / what |
|---|---|
| SearXNG | Docker container `searxng`, `searxng/searxng:latest`, `127.0.0.1:8888 -> 8080` |
| Compose project | `searxng/docker-compose.yml` |
| SearXNG config | `searxng/config/settings.yml` (`limiter: false`, `formats: [html, json]`; created by the installer from `settings.yml.example`) |
| MCP server | `npx -y mcp-searxng` (v2.5.0), `SEARXNG_URL=http://127.0.0.1:8888` |
| opencode | 1.18.34, config `~/.config/opencode/opencode.json` |
| Built-in search | disabled: `"tools": {"websearch": false}` |

Tools the agent sees:

| Tool | Purpose |
|---|---|
| `searxng_searxng_web_search` | search (`query`, `pageno`, `language`, `time_range`, `engines`, `num_results`, …) |
| `searxng_web_url_read` | read a page or PDF by URL |
| `searxng_searxng_search_suggestions` | autocomplete / query refinement |
| `searxng_searxng_instance_info` | list of SearXNG engines and categories |

Maintenance:

```bash
docker logs --tail 50 searxng                        # SearXNG logs
docker compose -f searxng/docker-compose.yml restart
docker compose -f searxng/docker-compose.yml pull && \
docker compose -f searxng/docker-compose.yml up -d   # update the image
```

Separate `npm exec mcp-searxng` processes in `ps aux` are normal: opencode spawns
one stdio process per session.

---

## 2. Deploying SearXNG from scratch

### Requirements

- Docker + `docker compose` v2
- Node.js **>= 22** and `npx` (for `mcp-searxng`)
- `python3` (edits `opencode.json`), `curl`, `openssl` (or python3) to generate the key

### Files

`searxng/docker-compose.yml` — SearXNG listens on loopback only; the port is set by
the `SEARXNG_PORT` variable (8888 by default):

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

`searxng/config/settings.yml` — `limiter: false` and JSON in `search.formats` are
mandatory, otherwise MCP will get 403/429:

```yaml
use_default_settings: true

general:
  instance_name: "MCP Search"
  donation_url: false
  contact_url: false

server:
  secret_key: "CHANGE_ME_GENERATED_BY_INSTALL_SH"   # replaced: openssl rand -hex 32
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

### Manual run

```bash
cd searxng
openssl rand -hex 32          # put the resulting key into secret_key
docker compose up -d
curl -s 'http://127.0.0.1:8888/search?q=test&format=json' | head -c 200
```

Or all at once with a single command (key, startup, MCP, disabling the built-in search):

```bash
bash opencode/scripts/install.sh
```

If `searxng/config/settings.yml` does not exist yet, the script creates it from
`settings.yml.example` and substitutes the generated `secret_key`.

---

## 3. Connecting the MCP server to opencode

The block in `~/.config/opencode/opencode.json` (global for all projects) or in a
project's `opencode.json`:

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

Alternative ways to launch it:

- global install: `npm i -g mcp-searxng`, then `"command": ["mcp-searxng"]` (no npx delay);
- Docker: `"command": ["docker", "run", "-i", "--rm", "-e", "SEARXNG_URL", "isokoliuk/mcp-searxng:latest"]`
  with `"environment": {"SEARXNG_URL": "http://127.0.0.1:8888"}` (inside a container the
  host loopback is reachable via `host.docker.internal`, which does not always work on
  Linux — npx is simpler).

Note: the first `npx` run downloads the package and may exceed opencode's initialization
timeout (5 s by default). So it helps to warm the cache:

```bash
npx -y mcp-searxng --version
```

If needed, raise the timeout with `"timeout": 20000` in the server block.

Verify the connection:

```bash
opencode mcp list        # expected: ✓ searxng connected
```

After editing the config, restart the opencode session.

---

## 4. Replacing the built-in search

opencode's built-in `websearch` is provided by a vendor provider and in this environment
answers with a 403 error. It is disabled with the `tools` key:

```json
{
  "tools": {
    "websearch": false
  }
}
```

Full resulting `opencode.json` (minimal version):

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

Nuances:

- only `websearch` is disabled; `webfetch` (fetching a known URL) stays and complements
  `searxng_web_url_read`;
- MCP tools can be toggled selectively: `"tools": {"searxng_*": false}` disables all
  tools of the server, `"tools": {"searxng_searxng_web_search": false}` disables one;
- to give the MCP tools to one specific agent only: disable globally
  (`"tools": {"searxng*": false}`) and enable in `agent.<name>.tools`.

---

## 5. Agent rules (AGENTS.md)

To make the model prefer MCP search on its own and never claim "search is unavailable",
add a snippet to `AGENTS.md` — the global `~/.config/opencode/AGENTS.md` (all projects)
or the project's root `AGENTS.md` (the snippet can be in any language):

```markdown
## Web search
- Web search is available through the `searxng` MCP server: `searxng_searxng_web_search`
  (search) and `searxng_web_url_read` (read a page or PDF).
- For externally verifiable facts (prices, rates, licenses, versions, statistics), search
  via `searxng_searxng_web_search` first and cite the source (URL). Only if the fact is
  not found, mark it as an "Assumption".
- The built-in `websearch` tool is disabled (`tools.websearch = false`) — this is expected.
  Do not claim "external search is unavailable" without calling `searxng_searxng_web_search`.
```

---

## 6. Scripts

| Script | What it does |
|---|---|
| `opencode/scripts/install.sh` | checks docker/node/python3, creates `searxng/config/settings.yml` from `settings.yml.example` and generates `secret_key` instead of the placeholder, starts the container, waits for the JSON API, warms the npx cache, writes `mcp.searxng` and `tools.websearch=false` into opencode.json (with a `*.bak-YYYYMMDD-HHMMSS` backup) |
| `opencode/scripts/verify.sh` | checks the container, JSON API, Node, `npx mcp-searxng`, the opencode config and `opencode mcp list`; exit code 1 on errors |

The SearXNG stack (`searxng/docker-compose.yml`, `searxng/config/`) lives at the
repository root and is shared by all recipes; the opencode scripts use it but do not
duplicate it.

Environment variables: `SEARXNG_PORT` (8888 by default), `OPENCODE_CONFIG`
(`~/.config/opencode/opencode.json` by default).

```bash
SEARXNG_PORT=8889 bash opencode/scripts/install.sh     # non-standard port
bash opencode/scripts/verify.sh
```

The scripts are idempotent: a repeated run does not duplicate blocks and does not
overwrite an already generated `secret_key`.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `opencode mcp list` does not show `searxng` / status failed | MCP process did not start (no Node >= 22, npx did not download the package) | `node -v`; manually run `npx -y mcp-searxng --version`; restart opencode |
| First tool call hangs/times out | cold npx cache, initialization > 5 s | warm it with `npx -y mcp-searxng --version` or set `"timeout": 20000` in the MCP block |
| `403 Forbidden`, `format is not allowed` | JSON is not enabled in SearXNG | in `settings.yml`: `search.formats: [html, json]`, then restart the container |
| `429 Too Many Requests` | `limiter` is enabled | `limiter: false` (only acceptable on loopback), restart |
| Empty results | engines serve a captcha/ban, or the query is too narrow | `docker logs searxng`; change the query/engine via `searxng_searxng_instance_info`; `safe_search: 0` |
| `secret_key` error in logs | key not set | `openssl rand -hex 32` into `settings.yml`, restart |
| Port 8888 busy | another service | `SEARXNG_PORT=8889 bash opencode/scripts/install.sh` (also updates `SEARXNG_URL`) |
| `PermissionError: /etc/searxng/settings.yml` in logs | the file is unreadable by the process: the container starts with `cap_drop: ALL` (no CAP_DAC_OVERRIDE), so mode `600/640` cannot be read | `sudo chmod 644 searxng/config/settings.yml`, then restart; do not tighten permissions manually |
| Cannot edit `settings.yml` after the first run | the `config/` directory is owned by uid 977 (the searxng user inside the container) | edit via `sudo`, e.g. `sudo nano searxng/config/settings.yml` |
| The agent still calls `websearch` | the rule was not added / the session is old | add the snippet from §5, restart opencode; if the built-in one returns 403 it is disabled as expected |
| `opencode.json` did not change after install.sh | it is JSONC with comments (a strict JSON parser cannot read them) | add the `mcp.searxng` block manually (§3); the script will restore the backup |
| Many `mcp-searxng` processes | normal: one process per client session | nothing to do |

---

## 8. Security and operations

- SearXNG binds to `127.0.0.1` only — the port is not exposed; this is intended.
- `secret_key` is a secret: `searxng/config/settings.yml` is created by the installer
  from `settings.yml.example` and is already in `.gitignore` — do not commit it.
  Rotation: replace the value and `docker compose restart searxng`.
- After the first run the `searxng/config/` directory becomes owned by uid 977
  (the `searxng` user inside the container) — edit via `sudo` only. The permissions on
  `settings.yml` must stay `644`: with `cap_drop: ALL` the container cannot bypass file
  permissions, and mode `600/640` will break startup.
- `limiter: false` is safe on loopback only. If you expose SearXNG publicly, enable
  `limiter`, `public_instance` and the protections from the SearXNG documentation.
- Update: `docker compose pull && docker compose up -d`; the MCP package updates by
  itself since `npx -y mcp-searxng` is used (pin the version if needed:
  `mcp-searxng@2.5.0`).
- Logs are capped (`max-size: 1m`, `max-file: 2`) — they will not fill the disk.

## Links

- opencode MCP: <https://opencode.ai/docs/mcp-servers/>
- mcp-searxng: <https://github.com/ihor-sokoliuk/mcp-searxng>
- SearXNG: <https://docs.searxng.org>
