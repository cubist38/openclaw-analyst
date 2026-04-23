# 🦞 Brewlytics — Multi-Agent Business Analyst

A team of four [OpenClaw](https://openclaw.com) agents that collaborate to answer business questions on a synthetic Starbucks database. A Telegram-bound **concierge** receives every message and routes to the right specialist — descriptive **analyst**, predictive **data-scientist**, or **customer-intel** — then relays the answer back.

Each agent has its own isolated workspace, its own memory, and a scoped exec allowlist.

## Architecture

```
                   ┌────────────────────────────┐
                   │  Telegram user              │
                   └────────────┬────────────────┘
                                │
                   ┌────────────▼────────────────┐
                   │  CONCIERGE  (main agent)     │  binds: telegram
                   │  greets, routes, relays      │  allowlist: invoke-specialist.sh
                   │  no SQL · no Python · no DB  │
                   └────────────┬────────────────┘
                                │  invoke-specialist.sh <agent> <session> <msg>
                   ┌────────────┼────────────┐
                   │            │            │
          ┌────────▼──────┐ ┌───▼──────────┐ ┌▼──────────────────┐
          │  ANALYST       │ │ DATA-        │ │ CUSTOMER-INTEL    │
          │  descriptive   │ │ SCIENTIST    │ │ loyalty / CLV /   │
          │  BI            │ │ forecasts,   │ │ retention          │
          │                │ │ stats,       │ │                    │
          │  6 skills      │ │ anomalies    │ │ 1 skill            │
          │                │ │ 2 skills     │ │                    │
          └────────┬───────┘ └──────┬───────┘ └──────┬─────────────┘
                   │                │                │
                   └────────────────┼────────────────┘
                                    │
                          ┌─────────▼──────────┐
                          │  shared SQLite DB   │
                          │  (symlinked in)     │
                          └─────────────────────┘
```

### Agents

| Agent | Role | Skills | Channel | Exec allowlist |
|---|---|---|---|---|
| **concierge** (`main`) | Front-desk router | — | Telegram | `invoke-specialist.sh` only |
| **analyst** | Descriptive BI | executive-summary, store-health, product-mix, marketing-roi, labor-analysis, compare | none (CLI-only) | sqlite3, python3 |
| **data-scientist** | Forecasts, stats, anomalies | trend, anomaly-scan | none | sqlite3, python3 |
| **customer-intel** | Loyalty, retention, CLV | customer-insights | none | sqlite3, python3 |

### Routing flow

1. User messages the Telegram bot
2. The concierge reads the message and either answers inline (trivia, greetings) or picks a specialist from `ROUTING.md`
3. It runs `./invoke-specialist.sh <agent> <session-id> <message>` — a locked-down wrapper around `openclaw agent --agent X --local`
4. The specialist queries the DB, runs analysis, generates charts (which `brew_chart.send()` pushes straight to Telegram), and writes its response to stdout
5. The concierge relays that response verbatim

One delegation per user turn. The specialist suggests a "Next Pour" — the user can follow up if they want depth in another domain.

### Security model

- **Concierge has no SQL, Python, or shell access.** Its only allowlisted executable is `invoke-specialist.sh`, which accepts exactly three specialist names and exactly the one-turn `--local -m` form. A compromised concierge cannot reconfigure OpenClaw, reach other agents arbitrarily, or run shell commands.
- **Specialists have no channel binding.** They can't read Telegram directly — they only run when the concierge invokes them. Chart delivery is the one intentional outbound path: `brew_chart.send()` can send generated PNGs to the requesting Telegram chat when the concierge passes a Telegram session id.
- **Each agent has its own workspace** (`~/.openclaw/workspace-{analyst,ds,customer}`). Memory races between specialists are impossible.
- **Single shared DB** (`~/.openclaw/shared-data/starbucks_business.db`) symlinked into each specialist. One source of truth, no drift.

## Prerequisites

- Linux (tested) or macOS
- Docker + Docker Compose (recommended) — or Node.js 22+ / Python 3.10+ / sqlite3 for a local install
- One inference backend: an [OpenRouter](https://openrouter.ai) API key, or a reachable OpenAI-compatible vLLM server
- A Telegram bot token (from [@BotFather](https://t.me/BotFather))
- Your Telegram numeric user ID (message [@userinfobot](https://t.me/userinfobot) to get it)

## Quick Start (Docker — recommended)

```bash
git clone https://github.com/cubist38/openclaw-analyst.git
cd openclaw-analyst

cp .env.example .env
# Edit .env with Telegram credentials and either OpenRouter or vLLM settings

docker compose up -d --build
```

On first boot the container:

- Starts as root only long enough to create and `chown` the mounted `openclaw-data` volume, then runs OpenClaw as the unprivileged `node` user
- Generates `openclaw.json` with all 4 agents using the current OpenClaw schema (`agents.defaults` + `agents.list`)
- Writes a per-agent `exec-approvals.json` (concierge: wrapper-only; specialists: `sqlite3` + `python3`)
- Generates the shared SQLite DB once at `~/.openclaw/shared-data/`
- Populates each of the 4 workspaces with the right files
- Starts the gateway with `gateway.mode=local` on port `18789`

Then message your Telegram bot: **"What are my top 5 stores by revenue?"** — the concierge routes it to `analyst`.

> **Tip:** Use your numeric Telegram user ID for `TELEGRAM_ALLOW_FROM` — the username resolver is unreliable. Get it from [@userinfobot](https://t.me/userinfobot).

Verify the container:

```bash
docker compose ps
docker compose exec analyst-bot node -e "fetch('http://127.0.0.1:18789/healthz').then(async r=>{console.log(r.status, await r.text()); process.exit(r.ok?0:1)}).catch(e=>{console.error(e); process.exit(1)})"
```

`docker compose ps` should eventually show `(healthy)`. The healthcheck has a `20s` start period and then runs every `30s`, so it may briefly show `(health: starting)` while OpenClaw finishes booting.

## Quick Start (Local)

```bash
git clone https://github.com/cubist38/openclaw-analyst.git
cd openclaw-analyst

# 1. Configure OpenClaw — creates the default 'main' agent and binds Telegram
openclaw configure

# 2. Install — provisions 3 specialist agents + populates all 4 workspaces
bash install.sh

# 3. Start
openclaw gateway run
```

`install.sh` is idempotent: re-run it to resync workspace files from the repo. It backs up `exec-approvals.json` before overwriting (security config — never silently replaced).

## Project Structure

```
openclaw-analyst/
├── README.md
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── docker/
│   └── entrypoint.sh             # multi-agent provisioning on first boot
├── install.sh                    # local install path
├── generate_starbucks_db.py      # synthetic DB generator (21 tables)
├── configs/config.yaml           # DB generation settings
├── requirements.txt
└── openclaw-config/
    ├── shared/                     # files used by more than one agent
    │   ├── BRAND.md                    # voice + universal rules ("Brewlytics")
    │   ├── DATA_ANALYST.md             # query discipline + response framework
    │   ├── MEMORY_RULES.md
    │   ├── invoke-specialist.sh        # concierge's locked-down wrapper
    │   └── data/
    │       ├── SCHEMA.md
    │       ├── brew_chart.py           # chart helper (auto-sends PNGs)
    │       └── send_photo.py
    └── agents/
        ├── concierge/                  # Telegram-bound router ('main')
        │   ├── SOUL.md, AGENTS.md
        │   ├── ROUTING.md              # when and how to delegate
        │   ├── GROUP_CHAT.md, HEARTBEAT_GUIDE.md
        ├── analyst/                    # descriptive BI
        │   ├── SOUL.md, AGENTS.md
        │   └── skills/{executive-summary, store-health, product-mix,
        │               marketing-roi, labor-analysis, compare}/
        ├── data-scientist/             # forecasts, stats, anomalies
        │   ├── SOUL.md, AGENTS.md
        │   ├── TECHNICAL_SKILLS.md     # EDA, modeling, forecasting, charts
        │   └── skills/{trend, anomaly-scan}/
        └── customer-intel/             # loyalty, retention, CLV
            ├── SOUL.md, AGENTS.md
            └── skills/customer-insights/
```

On disk after install:

```
~/.openclaw/
├── openclaw.json                 # 4 agents + Telegram + gateway
├── exec-approvals.json           # per-agent allowlists
├── shared-data/
│   └── starbucks_business.db     # canonical DB
├── workspace/                    # concierge (main)
├── workspace-analyst/            # analyst
├── workspace-ds/                 # data-scientist
└── workspace-customer/           # customer-intel
```

Each specialist workspace contains its own `SOUL.md`, `AGENTS.md`, `BRAND.md`, `DATA_ANALYST.md`, `MEMORY_RULES.md`, skills/, and a `data/` dir with `SCHEMA.md`, `brew_chart.py`, `send_photo.py`, `python3` (symlink), and `starbucks_business.db` (symlink to the canonical DB).

## Database Overview

Synthetic Starbucks business data — **no real customer or business information**. The default config generates 50 stores across 6 US regions for Q1 2026. Everything is configurable via `configs/config.yaml`.

With the default seed/config, the generator creates 21 business tables plus SQLite's internal `sqlite_sequence` table. A tested Docker first boot produced 52,985 total rows including `sqlite_sequence`.

| Table | Default Rows | Description |
|---|---|---|
| regions | 6 | US regions (Pacific NW, West, Southwest, Midwest, Southeast, Northeast) |
| stores | 50 | Locations with type (drive-thru/cafe/reserve), city, region |
| products | 60 | Full menu: espresso, cold brew, frappuccino, tea, refreshers, food, merch |
| employees | ~250 | Baristas, shift supervisors, store managers, district managers |
| customers | 200 | Rewards members with tiers (none/green/gold) |
| suppliers | 20 | Supply chain partners (beans, dairy, syrups, food, packaging) |
| daily_sales | 4,500 | Daily revenue per store |
| product_sales | 16,380 | Weekly product-level sales by sampled store/product combinations |
| customer_orders | ~1,600 | Individual orders with payment method and mobile flag |
| loyalty_transactions | ~1,300 | Stars earned/redeemed by rewards members |
| labor_schedule | ~15,000 | Shift records with overtime tracking |
| store_traffic | 9,100 | Hourly foot traffic with conversion rates |
| inventory | 2,400 | Monthly stock snapshots |
| financial_summary | 150 | Monthly P&L by store |
| customer_feedback | 200 | Ratings (1-5) by category |
| marketing_campaigns | 15 | Campaigns across email/social/in-store/app |
| waste_log | ~640 | Product waste by reason |
| delivery_orders | ~450 | Uber Eats / DoorDash orders |
| training_records | ~390 | Employee training completions |
| regional_performance | 12 | YoY regional comparison |
| menu_pricing_history | ~100 | Historical price changes |

### Configuring the Database

Edit `configs/config.yaml` to control what gets generated:

```yaml
seed: 42                    # Random seed for reproducibility
num_stores: 50
num_customers: 200
num_feedback: 200

employees_per_store:
  baristas_min: 2
  baristas_max: 4

date_range:
  start: "2026-01-01"
  end: "2026-03-31"

regions:
  - name: Pacific_NW
    cities:
      - { city: Seattle, state: WA }
      # ...
```

After editing, regenerate:

```bash
rm ~/.openclaw/shared-data/starbucks_business.db
bash install.sh          # local
```

For Docker, either reset the full persisted volume:

```bash
docker compose down -v
docker compose up -d --build
```

Or remove only the generated DB from the running container, then restart:

```bash
docker compose exec analyst-bot rm /home/node/.openclaw/shared-data/starbucks_business.db
docker compose restart
```

### Built-in Data Patterns

- **Top 20% of stores** perform ~20% above average
- **Bottom 10% of stores** perform ~30% below average (higher waste, worse feedback)
- **Seasonal products** (PSL, Peppermint Mocha, Gingerbread) decline across the date range
- **Weekend spikes** in revenue, Monday dips
- **~5% growth uplift** in the last third of the date range
- **Mobile orders** trend upward
- **Gold-tier customers** order 3–5× more frequently than non-members

## Example Questions

**Descriptive (→ analyst):**
- "What are my top 5 stores by revenue?"
- "Which products have the highest profit margin?"
- "Show me stores that are losing money and why"
- "Compare Uber Eats vs DoorDash"
- "Which stores have the most overtime?"
- "Give me a full Q1 executive summary"

**Predictive / inferential (→ data-scientist):**
- "Forecast revenue for the next 13 weeks with confidence intervals"
- "Run an A/B test analysis on email vs social campaigns"
- "Show me a correlation heatmap of all store metrics"
- "What if we raise prices 5% — model the revenue impact"
- "Which stores are statistical outliers and why?"

**Customer-side (→ customer-intel):**
- "How do gold members behave differently from green?"
- "Who are our top 10 customers by lifetime spend?"
- "What's the green-to-gold conversion opportunity?"

## Using Your Own Dataset

The agents are dataset-agnostic. To swap in your own:

1. Put your `.db` file at `~/.openclaw/shared-data/starbucks_business.db` (or edit the symlink targets in each workspace)
2. (Optional) Replace `openclaw-config/shared/data/SCHEMA.md` with your schema reference — if you skip this, the agents will auto-discover on first session
3. `SOUL.md` and `DATA_ANALYST.md` are generic SQL playbooks — they work with any SQLite DB. You may want to edit skills to match your domain.

## Channels

### Telegram

The default channel, bound to the **concierge** only. Specialists never see Telegram directly.

**Setup:**
1. Get a bot token from [@BotFather](https://t.me/BotFather)
2. Get your numeric user ID from [@userinfobot](https://t.me/userinfobot)
3. Set `.env`:
   ```bash
   TELEGRAM_BOT_TOKEN=123456789:ABC-DEF...
   TELEGRAM_ALLOW_FROM=123456789
   ```
4. Restart the container (or gateway)

Charts generated by specialists go directly to the requesting Telegram chat via `brew_chart.send()` — they don't route through the concierge. This is intentional: the concierge doesn't see images either (reducing its attack surface). If a request has no Telegram chat id, the PNG is saved locally instead of being broadcast to every allowed user.

### Zalo

[Zalo](https://docs.openclaw.ai/channels/zalo) is Vietnam's dominant messaging app and ships as a bundled OpenClaw plugin. To add it, bind the concierge to zalo:

```bash
openclaw agents bind main --channel zalo:default
```

Add the Zalo block to `~/.openclaw/openclaw.json`:

```json5
{
  channels: {
    zalo: {
      enabled: true,
      accounts: {
        default: {
          botToken: "123456789:abc-xyz",
          dmPolicy: "pairing"
        }
      }
    }
  }
}
```

Or via env var (Docker: add to `.env`):

```bash
ZALO_BOT_TOKEN=123456789:abc-xyz
```

Restart the gateway, then pair: message the bot on Zalo → get a one-time code → approve from the host:

```bash
openclaw pairing approve zalo <CODE>
```

**Zalo limits to be aware of:**
- Outbound text capped at 2000 characters (streaming disabled)
- Media uploads capped at `mediaMaxMb` (default 5)
- Group chats not supported for Marketplace bots

> **Charts on Zalo:** `brew_chart` and `send_photo.py` currently target Telegram only. For Zalo chart delivery, write a parallel uploader and call it from the specialist's chart scripts.

## Docker Details

The Docker path has been smoke-tested with Docker 29.4.0, Docker Compose v5.1.2, and the `ghcr.io/openclaw/openclaw:latest` image reporting OpenClaw 2026.4.21. The base image may move over time, so if OpenClaw changes its config schema again, reset the volume after updating this repo and rebuild.

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `OPENCLAW_PROVIDER` | No | `openrouter` or `vllm` (default: `openrouter`) |
| `OPENROUTER_API_KEY` | For OpenRouter | OpenRouter API key |
| `VLLM_API_KEY` | For vLLM | vLLM API key. Use any non-empty value if your server does not enforce auth |
| `VLLM_BASE_URL` | For remote vLLM | OpenAI-compatible vLLM `/v1` endpoint (Docker example: `http://host.docker.internal:8000/v1`) |
| `TELEGRAM_BOT_TOKEN` | Yes | Bot token from @BotFather |
| `TELEGRAM_ALLOW_FROM` | Yes | Your numeric Telegram user ID (comma-separated for multiple) |
| `OPENCLAW_MODEL` | No for OpenRouter, yes for vLLM | Model for all 4 agents. OpenRouter default: `openrouter/x-ai/grok-3-fast`; vLLM example: `vllm/meta-llama/Llama-3.1-8B-Instruct` |
| `VLLM_MODEL_NAME` | No | Display name for the configured vLLM model |
| `VLLM_CONTEXT_WINDOW` | No | Context window metadata for explicit vLLM config (default: `128000`) |
| `VLLM_MAX_TOKENS` | No | Max output metadata for explicit vLLM config (default: `8192`) |
| `VLLM_REASONING` | No | Set `true` only for vLLM-served reasoning models that should be marked as reasoning-capable |
| `TZ` | No | Timezone (default: `UTC`) |

### Inference Examples

OpenRouter:

```bash
OPENCLAW_PROVIDER=openrouter
OPENROUTER_API_KEY=sk-or-...
OPENCLAW_MODEL=openrouter/x-ai/grok-3-fast
```

vLLM on your host or LAN:

```bash
OPENCLAW_PROVIDER=vllm
OPENCLAW_MODEL=vllm/meta-llama/Llama-3.1-8B-Instruct
VLLM_API_KEY=vllm-local
VLLM_BASE_URL=http://host.docker.internal:8000/v1
VLLM_CONTEXT_WINDOW=128000
VLLM_MAX_TOKENS=8192
VLLM_REASONING=false
```

For Linux Docker hosts, this compose file maps `host.docker.internal` to the host gateway. For another machine, set `VLLM_BASE_URL` to a resolvable LAN hostname or IP, for example `http://192.168.1.50:8000/v1`.

### Persistent Data

> **Security note:** The `openclaw-data` volume contains your API key, bot token, and all 4 workspaces. Treat it like any other credential store.

Contents of `/home/node/.openclaw/`:
- `openclaw.json` — agent + channel config
- `exec-approvals.json` — per-agent allowlists
- `shared-data/starbucks_business.db` — canonical DB
- `workspace/`, `workspace-analyst/`, `workspace-ds/`, `workspace-customer/` — per-agent state

Workspace template files are re-copied from the image on every start to stay in sync with the repo. The DB, generated `openclaw.json`, generated approvals, and per-agent memory persist across restarts.

`openclaw.json` is generated only when the volume does not already contain one. If you change `OPENCLAW_PROVIDER`, `OPENCLAW_MODEL`, model credentials, `TELEGRAM_BOT_TOKEN`, or `TELEGRAM_ALLOW_FROM`, reset the volume with `docker compose down -v` before starting again. This is intentional: the volume contains credentials and runtime state, so the entrypoint does not silently overwrite it.

During boot, OpenClaw may rewrite `openclaw.json` to add runtime metadata, enable configured plugins, and generate `gateway.auth.token`. That is expected.

### Useful Commands

```bash
docker compose logs -f                     # view logs
docker compose up -d --build               # rebuild after editing configs
docker compose down -v && docker compose up -d --build   # full reset
docker compose exec analyst-bot bash       # shell into the container

# Verify gateway health from inside the container
docker compose exec analyst-bot node -e "fetch('http://127.0.0.1:18789/healthz').then(async r=>{console.log(r.status, await r.text()); process.exit(r.ok?0:1)}).catch(e=>{console.error(e); process.exit(1)})"

# Verify the generated DB through a specialist workspace symlink
docker compose exec analyst-bot sqlite3 /home/node/.openclaw/workspace-analyst/data/starbucks_business.db "select count(*) from stores; select count(*) from daily_sales;"

# Inspect generated config and approvals
docker compose exec analyst-bot python3 -m json.tool /home/node/.openclaw/openclaw.json
docker compose exec analyst-bot python3 -m json.tool /home/node/.openclaw/exec-approvals.json
```

### Control UI

The OpenClaw web UI is at `http://localhost:18789` when the container is running.

On the tested Docker Desktop setup, Docker reported `0.0.0.0:18789->18789/tcp` and the gateway health endpoint worked inside the container, but `curl http://127.0.0.1:18789/healthz` from the automation shell could still fail because of host/Docker port-forwarding behavior. If that happens, check `docker compose ps`, the internal health command above, and then open `http://localhost:18789` in your browser.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Unknown model: x-ai/grok-code-fast-1` | Run `openclaw configure` and pick a valid model, or set `OPENCLAW_MODEL` in `.env` |
| `Config invalid ... agents: Unrecognized keys` | You have an old generated `openclaw.json` in the Docker volume. This project now writes the current OpenClaw `agents.list` schema. Run `docker compose down -v && docker compose up -d --build` to regenerate. |
| `Gateway start blocked: existing config is missing gateway.mode` | Same root cause: stale generated config. Reset the Docker volume or set `gateway.mode` to `local` in `openclaw.json`. |
| `PermissionError: ... /home/node/.openclaw/openclaw.json` | Rebuild the image. The Docker entrypoint now fixes mounted volume ownership before dropping to the `node` user. |
| `docker compose ps` shows `(health: starting)` | Wait for OpenClaw to finish booting and for the first healthcheck. The healthcheck starts after 20s and then runs every 30s. |
| Host `curl localhost:18789/healthz` fails but container is healthy | Verify with `docker compose exec analyst-bot node -e "fetch('http://127.0.0.1:18789/healthz').then(async r=>console.log(r.status, await r.text()))"`. If that works and `docker compose ps` shows port `18789`, this is a host/Docker port-forwarding issue; try the browser or Docker Desktop settings. |
| Changed `.env` but container still uses old model/token | `openclaw.json` persists in the Docker volume. Run `docker compose down -v && docker compose up -d --build` to regenerate from `.env`. |
| vLLM config fails at startup | Use `OPENCLAW_PROVIDER=vllm`, set `OPENCLAW_MODEL` in `vllm/<model-id>` form, and point `VLLM_BASE_URL` at a reachable `/v1` endpoint. |
| `already running under launchd` | `openclaw daemon stop` first |
| Concierge answers business questions itself instead of routing | Check that `openclaw-config/agents/concierge/SOUL.md` and `ROUTING.md` are in `~/.openclaw/workspace/` — re-run `install.sh` or restart the container |
| Specialist can't query DB | `cat ~/.openclaw/exec-approvals.json` — the specialist agent should have sqlite3 + python3 in its allowlist. Re-run install to regenerate |
| Specialist can't generate charts | Check the `data/python3` symlink exists in the specialist workspace and points to the venv |
| Telegram `Could not resolve @username` | Use the numeric user ID from @userinfobot |
| `invoke-specialist.sh: command not found` (from concierge) | The wrapper wasn't copied to `~/.openclaw/workspace/invoke-specialist.sh` — re-run install |
| Specialist responds directly to Telegram instead of returning via concierge | The specialist was accidentally bound to telegram. Unbind: `openclaw agents unbind <name> --channel telegram` |

## License

MIT — see [LICENSE](LICENSE).
