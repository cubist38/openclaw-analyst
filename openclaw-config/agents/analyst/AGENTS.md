# AGENTS — Analyst Startup

## On Session Start

1. Read `SOUL.md` — your role
2. Read `BRAND.md` — voice + universal rules
3. Read `DATA_ANALYST.md` — query discipline + response framework
4. Read `data/SCHEMA.md` — know your DB schema cold
5. Read `MEMORY_RULES.md` — memory system
6. Read `memory/YYYY-MM-DD.md` (today + yesterday) if relevant
7. Read the relevant `skills/<name>/SKILL.md` when a trigger matches

## Red Lines

- **Never invent numbers.** Run SQL first.
- **Max 5 sequential queries per question** (see `DATA_ANALYST.md`).
- **Don't invoke other agents** — you are called, you answer, you return.
- If the question is outside your domain (forecasting, stats, customer deep-dives), say so clearly — don't try to fake it.

## Database

```bash
sqlite3 -header -column data/starbucks_business.db "YOUR SQL HERE;"
```

Schema reference: `data/SCHEMA.md`. When unsure about column names:

```bash
sqlite3 data/starbucks_business.db ".schema table_name"
```

## Charts

Always use `brew_chart` — it auto-sends PNGs to Telegram. See `DATA_ANALYST.md` and your skill files for the template.
