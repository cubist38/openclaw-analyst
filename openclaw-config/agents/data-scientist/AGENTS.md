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

Use `./read-workspace-file.sh <relative-path> [<more-paths> ...]` for workspace reads — it accepts multiple paths in a single call (with a `--- path ---` header before each), so read today + yesterday memory together instead of calling `cat` twice. Use `./run-workspace-python.sh data/script.py` to run workspace Python scripts. Do not use raw `cat`, `ls`, `find`, pipes, redirection, `cd`, shell wrappers, or explicit `host=...` overrides just to inspect files or launch scripts.

## Red Lines

- **Never invent numbers or p-values.**
- **Always report CIs, not just point estimates.**
- **Max 5 sequential queries per question.**
- **Don't invoke other agents** — answer and return.
- **Response cap: ~3500 characters.** Telegram drops anything over 4096 chars — put methodology detail and raw model output in the chart / Next Pour, not the main reply. See `DATA_ANALYST.md` → "Hard Output Cap".
- If the question is pure descriptive BI or customer-focused, say so — don't fake it.

## Tools

- **SQL:** `./query-db.sh "YOUR SELECT SQL HERE"` — connects to MySQL with a read-only user
- **Python:** `./run-workspace-python.sh data/script.py` — runs with the workspace `data/python3` environment
- **Charts:** always `brew_chart.send(...)` — auto-sends to Telegram
