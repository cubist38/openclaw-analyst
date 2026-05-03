# Brewlytics

OpenClaw multi-agent analytics bot for a synthetic Starbucks business database.

A Telegram-facing concierge receives each message, routes data questions to one
specialist agent, then relays the specialist's completed answer.

## What It Runs

| Agent | Handles |
|---|---|
| `main` / concierge | Telegram chat, routing, final replies |
| `analyst` | Revenue, stores, products, margins, labor, executive summaries |
| `data-scientist` | Forecasts, trends, anomalies, correlations, what-if analysis |
| `customer-intel` | Loyalty, retention, CLV, customer behavior |

Specialists query MySQL with a read-only user. The concierge has no database
tools, so it should route data questions instead of inventing answers.

## Requirements

- Docker and Docker Compose
- Telegram bot token from [@BotFather](https://t.me/BotFather)
- Your numeric Telegram user ID from [@userinfobot](https://t.me/userinfobot)
- At least one model backend:
  - OpenRouter API key, or
  - OpenAI-compatible vLLM server
  - Both, if you want to mix hosted and self-hosted models per agent

## Quick Start

```bash
git clone https://github.com/cubist38/openclaw-analyst.git
cd openclaw-analyst

cp .env.example .env
```

Edit `.env`:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOW_FROM=123456789

OPENCLAW_PROVIDER=openrouter
OPENROUTER_API_KEY=sk-or-...
OPENCLAW_MODEL=openrouter/x-ai/grok-3-fast

# Optional: override the model used by individual agents.
# Leave unset to fall back to OPENCLAW_MODEL.
OPENCLAW_CONCIERGE_MODEL=
OPENCLAW_ANALYST_MODEL=
OPENCLAW_DS_MODEL=
OPENCLAW_CUSTOMER_MODEL=

MYSQL_ROOT_PASSWORD=change-this-root-password
MYSQL_READONLY_PASSWORD=change-this-readonly-password
```

Generate the SQL seed files, then bring the database and bot up:

```bash
bash create_db.sh

# One-time: build the database. Takes ~3 min while 02_seed.sql imports.
docker compose --profile db up -d mysql

# Day-to-day: build/restart only the bot — the DB keeps running in the background.
docker compose up -d --build
```

The `mysql` service sits behind the `db` profile so plain
`docker compose up -d --build` rebuilds the bot without touching MySQL.
First boot of the database is the only slow step; afterwards the named
volume `mysql-data` keeps the seed and `up` is fast.

Verify:

```bash
docker compose ps
docker compose logs -f mysql
docker compose logs -f analyst-bot
```

When healthy, message your Telegram bot:

```text
What are my top 5 stores by revenue?
```

## vLLM Setup

Use this in `.env` when serving your own OpenAI-compatible model:

```bash
OPENCLAW_PROVIDER=vllm
OPENCLAW_MODEL=vllm/meta-llama/Llama-3.1-8B-Instruct
VLLM_API_KEY=vllm-local
VLLM_BASE_URL=http://host.docker.internal:8000/v1
VLLM_CONTEXT_WINDOW=128000
VLLM_MAX_TOKENS=8192
VLLM_REASONING=false
```

For a vLLM server on another machine, replace `host.docker.internal` with that
machine's LAN IP or hostname.

## Per-Agent Models

Docker and `install.sh` support different models for the concierge and each
specialist. The global `OPENCLAW_MODEL` is the fallback; set only the overrides
you need:

```bash
OPENCLAW_CONCIERGE_MODEL=openrouter/anthropic/claude-haiku-4.5
OPENCLAW_ANALYST_MODEL=openrouter/x-ai/grok-4.1-fast
OPENCLAW_DS_MODEL=openrouter/anthropic/claude-sonnet-4.5
OPENCLAW_CUSTOMER_MODEL=openrouter/anthropic/claude-haiku-4.5
```

Recommended split:

- `concierge`: use a fast, reliable instruction-follower. It mainly routes
  requests and must obey the specialist invocation rules.
- `analyst`: use a low-latency, cost-efficient model with a large context
  window. It handles most SQL-backed BI turns.
- `data-scientist`: use the strongest reasoning model you can afford. It owns
  forecasts, anomalies, correlations, tests, and what-if analysis.
- `customer-intel`: use a fast summarization and segmentation model unless
  customer cohort logic starts failing in practice.

Mixed providers are supported. For example, you can run SQL-heavy specialists
on a local vLLM model while keeping the concierge or data scientist on
OpenRouter:

```bash
OPENCLAW_PROVIDER=vllm
OPENCLAW_MODEL=vllm/Qwen/Qwen3-30B-A3B-Instruct-2507

OPENCLAW_CONCIERGE_MODEL=openrouter/anthropic/claude-haiku-4.5
OPENCLAW_ANALYST_MODEL=vllm/Qwen/Qwen3-30B-A3B-Instruct-2507
OPENCLAW_DS_MODEL=openrouter/anthropic/claude-sonnet-4.5
OPENCLAW_CUSTOMER_MODEL=vllm/Qwen/Qwen3-30B-A3B-Instruct-2507
```

If any configured model starts with `openrouter/`, set `OPENROUTER_API_KEY`.
If any configured model starts with `vllm/`, set the `VLLM_*` values.

## Common Commands

```bash
# Bring up the database (one-time, or after a host reboot)
docker compose --profile db up -d mysql

# Start or rebuild after code/config changes (bot only)
docker compose up -d --build

# Watch logs
docker compose logs -f analyst-bot
docker compose --profile db logs -f mysql

# Stop the bot, leave the DB running
docker compose down

# Stop everything (bot + DB), keep data
docker compose --profile db down

# Full reset: deletes OpenClaw state and MySQL data
docker compose --profile db down -v
docker compose --profile db up -d mysql
docker compose up -d --build

# Check gateway health from inside the bot container
docker compose exec analyst-bot node -e "fetch('http://127.0.0.1:18789/healthz').then(async r=>console.log(r.status, await r.text()))"

# Check database access through the analyst workspace
docker compose exec analyst-bot bash -lc 'cd /home/node/.openclaw/workspace-analyst && ./query-db.sh "select count(*) stores from stores; select count(*) daily_sales from daily_sales;"'
```

## Important Runtime Notes

- `openclaw-data` stores API keys, bot token, generated OpenClaw config,
  approvals, workspaces, and agent memory.
- `mysql-data` stores the generated MySQL database.
- MySQL imports `database/init/*.sql` only when `mysql-data` is empty.
- Model provider, model id, and API key changes are reconciled from `.env` when
  the bot container restarts. Telegram token and allow-list changes still
  require `docker compose down -v` so OpenClaw config is regenerated.
- Specialists are not bound to Telegram. They return stdout to the concierge.
- Charts generated by specialists are sent directly to Telegram when a Telegram
  chat id is available.

## Project Layout

```text
openclaw-analyst/
├── docker-compose.yml
├── Dockerfile
├── create_db.sh
├── generate_starbucks_db.py
├── database/init/              # generated MySQL schema and seed SQL
├── docker/entrypoint.sh         # provisions OpenClaw agents in Docker
├── install.sh                   # optional non-Docker install
├── configs/config.yaml          # synthetic data generation settings
└── openclaw-config/
    ├── shared/                  # shared prompts and helper scripts
    └── agents/
        ├── concierge/
        ├── analyst/
        ├── data-scientist/
        └── customer-intel/
```

## Database

The default generated dataset is synthetic. It creates:

- 50 Starbucks stores across 6 US regions
- Q1 2026 daily sales, traffic, labor, product sales, delivery, waste, and P&L
- 200 loyalty customers with transactions and feedback
- 21 MySQL tables and about 53k rows with the default config

To change the generated data, edit [configs/config.yaml](configs/config.yaml),
then regenerate and reset MySQL:

```bash
bash create_db.sh
docker compose --profile db down -v
docker compose --profile db up -d mysql
docker compose up -d --build
```

## Example Questions

```text
What are my top 5 stores by revenue?
Which products have the best profit margin?
Compare Uber Eats vs DoorDash.
Which stores have the most overtime?
Forecast revenue for the next 13 weeks.
Which stores are statistical outliers?
How do gold members behave differently from green members?
```

## Local Install

Docker is recommended. For a host install:

```bash
openclaw configure
bash install.sh
openclaw gateway run
```

Re-run `bash install.sh` after prompt, workspace file, or per-agent model
changes so the local OpenClaw config is reconciled.

## License

MIT. See [LICENSE](LICENSE).
