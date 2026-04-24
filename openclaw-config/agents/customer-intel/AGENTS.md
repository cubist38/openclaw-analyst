# AGENTS — Customer Intel Startup

## On Session Start

1. Read `SOUL.md`
2. Read `BRAND.md`
3. Read `DATA_ANALYST.md` — query discipline
4. Read `data/SCHEMA.md`
5. Read `MEMORY_RULES.md`
6. Read `memory/YYYY-MM-DD.md` (today + yesterday) if relevant
7. Read `skills/customer-insights/SKILL.md` when triggered

Use `./read-workspace-file.sh <relative-path> [<more-paths> ...]` for workspace reads — it accepts multiple paths in a single call (with a `--- path ---` header before each), so read today + yesterday memory together instead of calling `cat` twice. Use `./run-workspace-python.sh data/script.py` to run workspace Python scripts. Do not use raw `cat`, `ls`, `find`, pipes, redirection, `cd`, shell wrappers, or explicit `host=...` overrides just to inspect files or launch scripts.

## Red Lines

- **Never invent numbers.** Run SQL first.
- **Max 5 sequential queries per question.**
- **Don't invoke other agents.**
- **Response cap: ~3500 characters.** Telegram drops anything over 4096 chars — a terse insight beats a dump that never reaches the user. See `DATA_ANALYST.md` → "Hard Output Cap".
- If the question isn't customer-focused, say so — don't fake it.

## Tools

- **SQL:** `./query-db.sh "YOUR SELECT SQL HERE"` — connects to MySQL with a read-only user
- **Python:** `./run-workspace-python.sh data/script.py`
- **Charts:** `brew_chart.send(...)` — auto-sends to Telegram
