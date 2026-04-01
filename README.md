# OpenClaw Business Analyst Bot

An [OpenClaw](https://openclaw.com) agent configured as an expert Starbucks business data analyst. It queries a SQLite database with 20+ tables of realistic business data and delivers insights via Telegram.

## Prerequisites

- macOS (Homebrew)
- Python 3.10+
- Node.js 24+
- An [OpenRouter](https://openrouter.ai) API key
- A Telegram bot token (from [@BotFather](https://t.me/BotFather))
- Your Telegram numeric user ID (message [@userinfobot](https://t.me/userinfobot) to get it)

## Quick Start (Docker)

```bash
git clone https://github.com/cubist38/openclaw-analyst.git

cd openclaw-analyst

# 1. Create your .env file (never commit this file — it contains secrets)
cp .env.example .env
# Edit .env with your API key, Telegram bot token, and user ID

# 2. Start the bot
docker compose up -d
```

Then open Telegram, message your bot, and ask: **"What are my top 5 stores by revenue?"**

The container handles everything: installs dependencies, generates the database, configures OpenClaw, and starts the gateway.

> **Tip:** Get your Telegram numeric user ID from [@userinfobot](https://t.me/userinfobot) — use this for `TELEGRAM_ALLOW_FROM`, not your `@username`.

## Quick Start (Local)

```bash
git clone https://github.com/cubist38/openclaw-analyst.git

cd openclaw-analyst

# 1. Configure OpenClaw (interactive — sets up API key + Telegram bot)
openclaw configure

# 2. Install everything (config files, database, permissions)
bash install.sh

# 3. Start the bot
openclaw gateway run
```

> **Tip:** When prompted for Telegram `allowFrom` during `openclaw configure`, enter your **numeric user ID** (e.g. `123456789`), not your `@username`. Get it from [@userinfobot](https://t.me/userinfobot).

## Step-by-Step Setup

If you prefer to understand each step, or if the quick start doesn't work:

### 1. Install dependencies

```bash
bash setup.sh
```

Installs Node.js 24 (via Homebrew) and the OpenClaw CLI globally.

### 2. Configure OpenClaw

```bash
openclaw configure
```

Follow the prompts to set up:
- **OpenRouter** API key and model (e.g. `x-ai/grok-3-fast`)
- **Telegram** bot token and allowed user ID

> **Note:** When prompted for Telegram `allowFrom`, enter your **numeric user ID** (e.g. `123456789`), not your `@username`. The username resolver often fails.

### 3. Run the install script

```bash
bash install.sh
```

This single script handles everything:
- Checks that Node.js, Python 3, sqlite3, and OpenClaw are installed
- Verifies `openclaw configure` has been run
- Copies all config files into the OpenClaw workspace (always overwrites to stay in sync with repo)
- Generates the Starbucks SQLite database (skips if it already exists — delete the `.db` file to regenerate)
- Adds `sqlite3` and `python3` to the exec allowlist

**What gets installed:**

| File | Destination | Purpose |
|---|---|---|
| `openclaw-config/SOUL.md` | `~/.openclaw/workspace/SOUL.md` | Agent identity, response framework, guardrails & personality |
| `openclaw-config/DATA_ANALYST.md` | `~/.openclaw/workspace/DATA_ANALYST.md` | Analyst playbook — framework, query guardrails, anti-hallucination rules |
| `openclaw-config/TECHNICAL_SKILLS.md` | `~/.openclaw/workspace/TECHNICAL_SKILLS.md` | Advanced skills — EDA, modeling, forecasting, chart generation (matplotlib) |
| `openclaw-config/AGENTS.md` | `~/.openclaw/workspace/AGENTS.md` | Startup routine — slim entry point that loads role files |
| `openclaw-config/MEMORY_RULES.md` | `~/.openclaw/workspace/MEMORY_RULES.md` | Memory system — how to persist and curate memories |
| `openclaw-config/GROUP_CHAT.md` | `~/.openclaw/workspace/GROUP_CHAT.md` | Group chat behavior — when to speak, reactions, formatting |
| `openclaw-config/HEARTBEAT_GUIDE.md` | `~/.openclaw/workspace/HEARTBEAT_GUIDE.md` | Heartbeat system — proactive checks and background work |
| `openclaw-config/skills/` | `~/.openclaw/workspace/skills/` | Analyst skills (9 skills, one `SKILL.md` per folder) |
| `openclaw-config/data/SCHEMA.md` | `~/.openclaw/workspace/data/SCHEMA.md` | Database schema reference |
| _(generated)_ | `~/.openclaw/workspace/data/starbucks_business.db` | SQLite database with 21 tables |

> **Note:** Config files always overwrite the workspace copies to stay in sync with the repo. The database is only generated once — to regenerate, delete `~/.openclaw/workspace/data/starbucks_business.db` and re-run `install.sh`.

### 4. Start the bot

**Foreground** (see logs directly):

```bash
openclaw gateway run
```

**Background** (as a daemon):

```bash
openclaw daemon start
```

To stop: `openclaw daemon stop`
To restart: `openclaw daemon stop && openclaw gateway run`

> **Note:** If you see `already running under launchd`, stop the daemon first with `openclaw daemon stop`, then run `openclaw gateway run`.

### 5. Chat with your bot

Open Telegram, find your bot, and start asking business questions.

## Database Overview

The database simulates a Starbucks operation with entirely **synthetic data** — no real customer or business information is used. With the default config, it generates 50 stores across 6 US regions for Q1 2026 — but all of this is configurable via `configs/config.yaml`.

| Table | Default Rows | Description |
|---|---|---|
| regions | 6 | US regions (Pacific NW, West, Southwest, Midwest, Southeast, Northeast) |
| stores | 50 | Locations with type (drive-thru/cafe/reserve), city, region |
| products | 60 | Full menu: espresso, cold brew, frappuccino, tea, refreshers, food, merch |
| employees | ~250 | Baristas, shift supervisors, store managers, district managers |
| customers | 200 | Rewards members with tiers (none/green/gold) |
| suppliers | 20 | Supply chain partners (beans, dairy, syrups, food, packaging) |
| daily_sales | 4,500 | Daily revenue per store (stores x days in range) |
| product_sales | 3,900 | Weekly product-level sales by store |
| customer_orders | ~1,700 | Individual orders with payment method and mobile flag |
| loyalty_transactions | ~1,300 | Stars earned/redeemed by rewards members |
| labor_schedule | ~15,000 | Shift records with overtime tracking |
| store_traffic | 9,100 | Hourly foot traffic with conversion rates |
| inventory | 2,400 | Monthly stock snapshots (months x stores x 16 items) |
| financial_summary | 150 | Monthly P&L by store (revenue, COGS, labor, rent, etc.) |
| customer_feedback | 200 | Ratings (1-5) by category (service/quality/speed/cleanliness/app) |
| marketing_campaigns | 15 | Campaigns across email/social/in-store/app (filtered to date range) |
| waste_log | ~660 | Product waste by reason (expired/damaged/overproduction/quality) |
| delivery_orders | ~500 | Uber Eats / DoorDash orders with delivery time and ratings |
| training_records | ~360 | Employee training completions with scores |
| regional_performance | 12 | YoY regional comparison (auto-generated from date range) |
| menu_pricing_history | ~100 | Historical price changes with reasons |

### Configuring the Database

Edit `configs/config.yaml` to control what gets generated:

```yaml
seed: 42                    # Random seed for reproducibility
num_stores: 50              # Number of store locations
num_customers: 200          # Number of rewards customers
num_feedback: 200           # Number of feedback entries

employees_per_store:
  baristas_min: 2
  baristas_max: 4

date_range:
  start: "2026-01-01"      # Any start date
  end: "2026-03-31"        # Any end date — even multi-year

regions:                    # Add/remove regions and cities
  - name: Pacific_NW
    cities:
      - city: Seattle
        state: WA
      # ...
```

**Key points:**
- **Date range** can span any duration — weeks, months, or years. All transactional tables (daily_sales, orders, deliveries, labor, inventory, financials) adapt automatically.
- **Regions and cities** are fully configurable. Add new regions or remove existing ones.
- **Store performance thresholds** scale proportionally — top 20% are high performers, bottom 10% are struggling.
- **`db_path`** can override the output location if you want to generate the database elsewhere.

After editing the config, delete the existing database and re-run:

```bash
rm ~/.openclaw/workspace/data/starbucks_business.db
bash install.sh
```

### Built-in Data Patterns

The data has intentional patterns for the bot to discover:

- **Top 20% of stores** perform ~20% above average (top performers)
- **Bottom 10% of stores** perform ~30% below average (struggling, higher waste, worse feedback)
- **Seasonal products** (PSL, Peppermint Mocha, Gingerbread) decline over the date range
- **Weekend spikes** in revenue, Monday dips
- **Growth trend** ~5% uplift in the last third of the date range
- **Mobile orders** trend upward over time
- **Delivery volume** grows over time
- **Gold tier customers** order 3-5x more frequently than non-members

## Example Questions

Ask your bot things like:

**Business Analysis:**
- "What are my top 5 stores by revenue?"
- "Which products have the highest profit margin?"
- "Show me stores that are losing money and why"
- "Compare Uber Eats vs DoorDash — which is better?"
- "What's our marketing ROI by channel?"
- "Which stores have the most overtime?"
- "What are customers complaining about?"
- "How do gold members behave differently from green?"
- "Give me a full Q1 executive summary"

**Advanced Analytics (Technical Skills):**
- "Forecast revenue for the next 13 weeks with confidence intervals"
- "Run an A/B test analysis on our email vs social campaigns"
- "Show me a correlation heatmap of all store metrics"
- "What if we raise prices 5% — model the revenue impact"
- "Brew me a pour-over trend of mobile order adoption"
- "Give me a cold brew forecast with best/worst case scenarios"
- "Which stores are statistical outliers and why?"

## Project Structure

```
openclaw-analyst/
├── README.md                   # This file
├── Dockerfile                  # Docker image build
├── docker-compose.yml          # Docker Compose setup
├── .env.example                # Environment variables template
├── docker/
│   └── entrypoint.sh           # Container startup script
├── install.sh                  # Local setup (copies configs, generates DB, sets permissions)
├── create_db.sh                # Generate the SQLite database only
├── generate_starbucks_db.py    # Python data generation logic (21 tables, config-driven)
├── requirements.txt            # Python dependencies (pyyaml, pandas, matplotlib, seaborn)
├── configs/
│   └── config.yaml             # Database generation config (stores, regions, date range, etc.)
├── openclaw-config/            # Bot persona & analyst config files
│   ├── SOUL.md                 # Agent identity, response framework, guardrails & personality
│   ├── DATA_ANALYST.md         # Analyst playbook (framework, query guardrails, anti-hallucination)
│   ├── TECHNICAL_SKILLS.md     # Advanced skills (EDA, modeling, forecasting, charting, tools)
│   ├── AGENTS.md               # Startup routine — slim entry point that loads other files
│   ├── MEMORY_RULES.md         # Memory system (daily logs, long-term memory, write-it-down rules)
│   ├── GROUP_CHAT.md           # Group chat behavior (when to speak, reactions, formatting)
│   ├── HEARTBEAT_GUIDE.md      # Heartbeat system (proactive checks, cron vs heartbeat)
│   ├── skills/                 # Analyst skills (one SKILL.md per folder)
│   │   ├── executive-summary/
│   │   ├── store-health/
│   │   ├── product-mix/
│   │   ├── customer-insights/
│   │   ├── marketing-roi/
│   │   ├── labor-analysis/
│   │   ├── anomaly-scan/
│   │   ├── trend/
│   │   └── compare/
│   └── data/
│       └── SCHEMA.md           # Database schema reference & relationships
└── .gitignore
```

OpenClaw workspace files (created by `openclaw configure` + this project):

```
~/.openclaw/
├── openclaw.json               # Main config (model, Telegram, gateway)
├── exec-approvals.json         # Exec permissions (sqlite3 allowlist)
└── workspace/
    ├── AGENTS.md               # Startup routine (slim — references other files)
    ├── SOUL.md                 # Agent identity, response framework, guardrails & personality
    ├── USER.md                 # User profile
    ├── DATA_ANALYST.md         # Analyst playbook (framework, query guardrails)
    ├── TECHNICAL_SKILLS.md     # Advanced skills (EDA, modeling, forecasting, charting, tools)
    ├── MEMORY_RULES.md         # Memory system (daily logs, long-term memory)
    ├── GROUP_CHAT.md           # Group chat behavior (loaded only in group context)
    ├── HEARTBEAT_GUIDE.md      # Heartbeat system (loaded only on heartbeat)
    ├── skills/                 # Analyst skills (one SKILL.md per folder)
    ├── TOOLS.md                # Environment-specific notes
    ├── MEMORY.md               # Curated long-term memory (main session only)
    ├── memory/                 # Daily logs (one file per day)
    └── data/
        ├── starbucks_business.db   # SQLite database (configurable size)
        └── SCHEMA.md               # Full schema reference & relationships
```

## How It Works

1. **OpenClaw gateway** runs and connects to Telegram via bot token
2. When you message the bot, the agent reads its workspace files (`SOUL.md`, `DATA_ANALYST.md`, `TECHNICAL_SKILLS.md`, etc.) to understand its role
3. The agent runs `sqlite3` queries against the database to answer your questions
4. For visual analysis, the agent generates Python scripts with matplotlib/seaborn, renders PNG charts, and displays them inline in Telegram
5. It delivers insights with recommendations, not just raw numbers

### How OpenClaw Workspace Files Relate

```
AGENTS.md (entry point — slim startup routine)
  │
  ├── reads SOUL.md            → WHO the bot is (identity, response framework, guardrails)
  ├── reads USER.md            → WHO it's helping (your profile)
  ├── reads DATA_ANALYST.md    → WHAT it does (analyst playbook + query guardrails)
  ├── reads TECHNICAL_SKILLS.md → HOW it levels up (EDA, modeling, forecasting, charting)
  ├── reads skills/*/SKILL.md  → HOW it analyzes (9 analytical skills)
  ├── reads MEMORY_RULES.md    → HOW memory works (always loaded)
  ├── reads memory/            → WHAT it remembers (daily logs)
  ├── reads MEMORY.md          → Long-term memory (main session only)
  ├── reads GROUP_CHAT.md      → Group behavior (group chats only)
  └── reads HEARTBEAT_GUIDE.md → Proactive checks (heartbeats only)
```

| File | Purpose | Customizable? |
|---|---|---|
| `AGENTS.md` | Startup sequence, red lines | Rarely — core OpenClaw behavior |
| `SOUL.md` | Identity, response framework & guardrails | Yes — swap for different persona |
| `DATA_ANALYST.md` | Analyst playbook + query guardrails | Yes — replace for different use case |
| `TECHNICAL_SKILLS.md` | Advanced skills (EDA, modeling, forecasting, charting) | Yes — add/remove capabilities |
| `skills/*/SKILL.md` | Analytical skills (9 skills) | Yes — add/remove/edit skill folders |
| `MEMORY_RULES.md` | Memory system rules | Rarely — how the bot persists context |
| `GROUP_CHAT.md` | Group chat behavior | Yes — tune when/how bot participates |
| `HEARTBEAT_GUIDE.md` | Proactive checks & background work | Yes — configure what to monitor |
| `data/SCHEMA.md` | Database schema reference | Yes — auto-generated if missing |
| `TOOLS.md` | Environment notes (SSH, devices, etc.) | Per machine |
| `USER.md` | Info about the human | Per user |
| `MEMORY.md` | Curated long-term memory | Bot maintains this itself |

### Using Your Own Dataset

You don't need the Starbucks data. To use your own:

1. Place your `.db` file in `~/.openclaw/workspace/data/`
2. (Optional) Write a `data/SCHEMA.md` describing your tables — if you skip this, the bot will auto-discover the schema on first session and create `SCHEMA.md` itself
3. `SOUL.md` and `DATA_ANALYST.md` are generic — they work with any SQLite database

### Multi-User / Group Chat Setup

By default, the bot uses a single agent (`main`) with one shared workspace. This works fine for 1-on-1 DMs, but **group chats with multiple people can cause race conditions** when the bot writes to shared files like `MEMORY.md` or daily logs.

**How sessions work:**

| Session type | Example | Reads MEMORY.md? | Write-safe? |
|---|---|---|---|
| Main session | Your Telegram DM | Yes | Yes (single user) |
| Group chat | Telegram group | No | Risk of conflicts |
| Cron job | Scheduled task | No | Risk of conflicts |

**Solution: isolate agents per context**

Create a separate agent for group chats with its own workspace:

```bash
# Create a group chat agent with isolated workspace
openclaw agents add analyst-group \
  --workspace ~/.openclaw/workspace-group \
  --model openrouter/x-ai/grok-3-fast \
  --bind telegram:group

# Copy config files to the new workspace
cp openclaw-config/SOUL.md ~/.openclaw/workspace-group/SOUL.md
cp openclaw-config/DATA_ANALYST.md ~/.openclaw/workspace-group/DATA_ANALYST.md
cp openclaw-config/TECHNICAL_SKILLS.md ~/.openclaw/workspace-group/TECHNICAL_SKILLS.md
cp openclaw-config/AGENTS.md ~/.openclaw/workspace-group/AGENTS.md
cp openclaw-config/MEMORY_RULES.md ~/.openclaw/workspace-group/MEMORY_RULES.md
cp openclaw-config/GROUP_CHAT.md ~/.openclaw/workspace-group/GROUP_CHAT.md
cp openclaw-config/HEARTBEAT_GUIDE.md ~/.openclaw/workspace-group/HEARTBEAT_GUIDE.md
cp -r openclaw-config/skills ~/.openclaw/workspace-group/skills
mkdir -p ~/.openclaw/workspace-group/data
cp ~/.openclaw/workspace/data/starbucks_business.db ~/.openclaw/workspace-group/data/
cp openclaw-config/data/SCHEMA.md ~/.openclaw/workspace-group/data/SCHEMA.md
```

This gives you:
- `main` agent → your private DM (full memory access)
- `analyst-group` agent → group chats (isolated workspace, no conflicts)

Each agent has its own workspace, memory, and session state — no race conditions.

## Docker Details

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `OPENROUTER_API_KEY` | Yes | Your OpenRouter API key |
| `TELEGRAM_BOT_TOKEN` | Yes | Bot token from [@BotFather](https://t.me/BotFather) |
| `TELEGRAM_ALLOW_FROM` | Yes | Your numeric Telegram user ID |
| `OPENCLAW_MODEL` | No | Model to use (default: `openrouter/x-ai/grok-3-fast`) |
| `TZ` | No | Timezone (default: `UTC`) |

### Persistent Data

> **Security note:** The `openclaw-data` volume contains your API key and bot token in `openclaw.json`. Treat it like any other credential store — do not share or expose it.

The `openclaw-data` Docker volume persists all state at `/home/node/.openclaw/`:
- `openclaw.json` — gateway config (auto-generated on first run)
- `exec-approvals.json` — sqlite3 allowlist (auto-generated)
- `workspace/` — agent workspace, memory, and database

Config files (AGENTS.md, SOUL.md, etc.) are re-copied from the image on every start to stay in sync. The database is only generated once.

### Useful Commands

```bash
# View logs
docker compose logs -f

# Rebuild after changing config files or code
docker compose up -d --build

# Reset everything (database, config, memory)
docker compose down -v
docker compose up -d

# Shell into the container
docker compose exec analyst-bot bash
```

### Control UI

The OpenClaw web UI is available at `http://localhost:18789` when the container is running.

## Troubleshooting

| Problem | Solution |
|---|---|
| `Unknown model: x-ai/grok-code-fast-1` | Run `openclaw configure` and pick a valid model (e.g. `x-ai/grok-3-fast`) |
| `already running under launchd` | Run `openclaw daemon stop` first |
| Bot doesn't query the database | Check `openclaw approvals get` — sqlite3 must be in the allowlist |
| Bot can't generate charts | Check `openclaw approvals get` — python3 must be in the allowlist. Re-run `install.sh` to fix |
| Telegram `Could not resolve @username` | Use your numeric user ID instead (get it from @userinfobot) |
| Bot replies but with no data insights | Restart the gateway so it picks up the new workspace files |

## License

This project is licensed under the [MIT License](LICENSE).
