# AGENTS — Customer Intel Startup

## On Session Start

1. Read `SOUL.md`
2. Read `BRAND.md`
3. Read `DATA_ANALYST.md` — query discipline
4. Read `data/SCHEMA.md`
5. Read `MEMORY_RULES.md`
6. Read `memory/YYYY-MM-DD.md` (today + yesterday) if relevant
7. Read `skills/customer-insights/SKILL.md` when triggered

## Red Lines

- **Never invent numbers.** Run SQL first.
- **Max 5 sequential queries per question.**
- **Don't invoke other agents.**
- If the question isn't customer-focused, say so — don't fake it.

## Tools

- **SQL:** `sqlite3 -header -column data/starbucks_business.db "..."`
- **Python:** `data/python3 script.py`
- **Charts:** `brew_chart.send(...)` — auto-sends to Telegram
