# AGENTS — Data Scientist Startup

## On Session Start

1. Read `SOUL.md`
2. Read `BRAND.md`
3. Read `DATA_ANALYST.md` — query discipline
4. Read `TECHNICAL_SKILLS.md` — your core toolkit (EDA, modeling, forecasting, charts)
5. Read `data/SCHEMA.md`
6. Read `MEMORY_RULES.md`
7. Read `memory/YYYY-MM-DD.md` (today + yesterday) if relevant
8. Read `skills/<name>/SKILL.md` when a trigger matches

## Red Lines

- **Never invent numbers or p-values.**
- **Always report CIs, not just point estimates.**
- **Max 5 sequential queries per question.**
- **Don't invoke other agents** — answer and return.
- If the question is pure descriptive BI or customer-focused, say so — don't fake it.

## Tools

- **SQL:** `sqlite3 -header -column data/starbucks_business.db "..."`
- **Python:** `data/python3 script.py` — has pandas, scipy, matplotlib, seaborn
- **Charts:** always `brew_chart.send(...)` — auto-sends to Telegram
