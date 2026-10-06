# Web search via MCP: SearXNG + mcp-searxng + Codex

[Русская версия](README.ru.md)

Runs the shared SearXNG stack and connects its search and page-reading tools to
Codex CLI over stdio. Tested on Linux, Codex CLI **0.160.1**, MCP server **2.5.1**,
and SearXNG **2026.10.4-d48c4b555** (2026-10-06). The Docker launcher was tested
end to end with `initialize`, `tools/list`, and a real `tools/call` search.

```text
Codex → stdio → docker run -i mcp-searxng → HTTP → SearXNG → search engines
```

## 1. Install and verify

Requirements: Linux, Docker with Compose v2 or newer, access to the Docker daemon,
Codex CLI, Python >= 3.11, `curl`, and internet access for image downloads/search.
Node.js on the host is unnecessary for the default Docker launcher.
Run as your normal Codex user, with permission to access Docker, rather than using
`sudo` for the entire installer (which would configure root's Codex).

From the repository root:

```bash
bash codex/scripts/install.sh
bash codex/scripts/verify.sh
```

The installer creates `searxng/config/settings.yml` and generates the secret key
only when needed, starts the shared container, waits for JSON search responses,
backs up the existing Codex configuration, and adds the global `searxng` MCP
server using `codex mcp add`. It replaces an existing server of that name.
Other Codex settings and MCP servers are preserved. Repeated runs reuse the key
and container. The final verification must receive search results with source URLs.

Docker MCP defaults to an image digest, so subsequent runs use the same artifact.
SearXNG still uses the shared Compose stack's `latest` tag. Updating either
component is an explicit maintenance step; see below.

Restart the Codex session after installation. Run `/mcp` to see the active tools,
then ask: "Use the searxng MCP server to find the SearXNG installation docs and cite
the source URLs." Add the rules from [AGENTS.md.example](AGENTS.md.example) to
your project's `AGENTS.md` or global `~/.codex/AGENTS.md` so Codex prefers MCP search.
The installer does not edit your agent rules.

## 2. Configuration

Codex stores the server in `${CODEX_HOME:-~/.codex}/config.toml`.
The CLI and IDE extension share the configuration. For manual setup, merge
[config.toml.example](config.toml.example) into that file; do not replace the whole
file. The example includes longer timeouts for slow machines. The installer uses
the Codex default timeouts and pulls the image before registration.

Equivalent registration after SearXNG is running:

```bash
docker pull isokoliuk/mcp-searxng@sha256:47c2c520c06b396b89d34bda8a4cd5961e04e4d35c59b931f63d617be45245b5
codex mcp add searxng --env SEARXNG_URL=http://127.0.0.1:8888 --env MCP_HTTP_PORT= -- \
  docker run --rm -i --network host -e SEARXNG_URL -e MCP_HTTP_PORT= \
  isokoliuk/mcp-searxng@sha256:47c2c520c06b396b89d34bda8a4cd5961e04e4d35c59b931f63d617be45245b5
codex mcp get searxng --json
codex mcp list
```

`-i` keeps stdin open for MCP; omit `-t` because a TTY breaks the stdio protocol.
`--network host` lets the MCP container reach SearXNG on the Linux host loopback.
Docker must run on the same machine as Codex; a remote Docker daemon has a
different loopback and cannot use this recipe unchanged. `MCP_HTTP_PORT` is cleared
to keep MCP in stdio mode. SearXNG's HTTP endpoint is **not** an MCP endpoint:
do not register `http://127.0.0.1:8888` with `codex mcp add --url`.

`codex mcp list` shows registration, not a successful connection or tool call.
The verifier starts the configured command, completes the MCP handshake, checks
all four tools, and performs a search without requiring an LLM or extra Python
packages. Temporary stdio processes are closed after verification. During normal
use Codex starts an MCP process per session; no separate MCP daemon is needed.

| MCP tool | Purpose |
|---|---|
| `searxng_web_search` | Search with query, language, engine and time filters |
| `web_url_read` | Read a web page or PDF |
| `searxng_search_suggestions` | Query suggestions |
| `searxng_instance_info` | Available engines and categories |

Codex may display tools with a server prefix; use `/mcp` for their actual names.

## 3. Options and npx launcher

| Variable | Default | Purpose |
|---|---|---|
| `SEARXNG_PORT` | `8888` | Shared SearXNG loopback port; also set when verifying |
| `MCP_LAUNCHER` | `docker` | `docker` or `npx` |
| `MCP_IMAGE` | Digest in the example | Docker MCP image |
| `MCP_PACKAGE` | `mcp-searxng@2.5.1` | npx package version |
| `CODEX_HOME` | `~/.codex` | Codex configuration directory |

```bash
SEARXNG_PORT=8889 bash codex/scripts/install.sh
SEARXNG_PORT=8889 bash codex/scripts/verify.sh
```

Changing the port moves the **shared** container; update other agent recipes using
it as well.

With Node.js >= 22, npm and npx on the host (also an option for macOS/Docker Desktop):

```bash
MCP_LAUNCHER=npx bash codex/scripts/install.sh
```

The installer warms the package cache, records the absolute npx executable path,
and registers this command:

```bash
codex mcp add searxng --env SEARXNG_URL=http://127.0.0.1:8888 --env MCP_HTTP_PORT= -- \
  npx -y mcp-searxng@2.5.1
```

For manual TOML setup replace `command` with `"npx"` and `args` with
`["-y", "mcp-searxng@2.5.1"]`; keep the environment table and timeouts. Restart
Codex after changes. The verification uses the command saved in Codex's configuration,
so it works with either launcher. Desktop platforms were not tested in this recipe.

The recipe leaves Codex's built-in web search preference unchanged. To use only MCP
search for a session, run `codex -c 'web_search="disabled"'`; manual global setup can
set `web_search = "disabled"` **at the top level** of `config.toml`. Agent rules
still help select the MCP tools.

## 4. Troubleshooting and maintenance

| Symptom | Action |
|---|---|
| Docker permission denied | Give your user access to the daemon; do not configure Codex as root |
| MCP missing in the current session | Restart Codex, inspect `/mcp`, then run `codex mcp get searxng --json` |
| Initialization timeout | Pull/cache the image or package first; set `startup_timeout_sec = 30` in the MCP table |
| JSON API 403/429 | Ensure `search.formats` includes `json` and `server.limiter: false`, then restart SearXNG |
| Search returns no results | Inspect `docker logs --tail 50 searxng`; try a different query/engine. Captchas or rate limits on some engines do not prevent others from returning results |
| Port occupied | Set `SEARXNG_PORT` for both install and verify |
| Cannot edit settings after startup | The container may chown the config directory to uid 977; edit with appropriate permissions. Keep settings mode 644 for the Compose capabilities |
| Codex is remote or in another container | `127.0.0.1` refers to that environment; run this stack there or configure reachable networking explicitly |

```bash
docker logs --tail 50 searxng
docker compose -f searxng/docker-compose.yml restart searxng
# Update the shared SearXNG image:
docker compose -f searxng/docker-compose.yml pull
docker compose -f searxng/docker-compose.yml up -d
# Opt in to a new MCP image, register it, and rerun the search check:
MCP_IMAGE=isokoliuk/mcp-searxng:latest bash codex/scripts/install.sh
# Remove Codex registration (leaves the shared SearXNG service running):
codex mcp remove searxng
```

SearXNG binds only to `127.0.0.1`; no public MCP port is opened. The generated
settings contain a secret and are gitignored. Disabling the SearXNG limiter is
appropriate only for this local deployment. Searches go to external engines,
and page reading fetches external sites directly.

## Sources

- [Official OpenAI documentation: Codex MCP](https://developers.openai.com/codex/mcp/)
- [Codex configuration reference](https://developers.openai.com/codex/config-reference/)
- [mcp-searxng upstream](https://github.com/ihor-sokoliuk/mcp-searxng)
- [SearXNG documentation](https://docs.searxng.org)
