# AGENTS — Analyst Startup

## On Session Start

1. Read `SOUL.md` — your role
2. Read `BRAND.md` — voice + universal rules
3. Read `DATA_ANALYST.md` — query discipline + response framework
4. Read `data/SCHEMA.md` — know your DB schema cold
5. Read `MEMORY_RULES.md` — memory system
6. Read `memory/YYYY-MM-DD.md` (today + yesterday) if relevant
7. Read the relevant `skills/<name>/SKILL.md` when a trigger matches

Use `./read-workspace-file.sh <relative-path> [<more-paths> ...]` for workspace reads — it accepts multiple paths in a single call (with a `--- path ---` header before each), so read today + yesterday memory together instead of calling `cat` twice. Use `./run-workspace-python.sh data/script.py` to run workspace Python scripts. Do not use raw `cat`, `ls`, `find`, pipes, redirection, `cd`, shell wrappers, or explicit `host=...` overrides just to inspect files or launch scripts.

## Red Lines

- **Never invent numbers.** Run SQL first.
- **Max 5 sequential queries per question** (see `DATA_ANALYST.md`).
- **Don't invoke other agents** — you are called, you answer, you return.
- **Response cap: ~3500 characters.** Telegram drops anything over 4096 chars — a terse insight beats a dump that never reaches the user. See `DATA_ANALYST.md` → "Hard Output Cap".
- If the question is outside your domain (forecasting, stats, customer deep-dives), say so clearly — don't try to fake it.

## Database

```bash
./query-db.sh "YOUR SELECT SQL HERE;"
```

Schema reference: `data/SCHEMA.md`. When unsure about column names:

```bash
./query-db.sh "DESCRIBE table_name;"
```

## Charts

Always use `brew_chart` — it auto-sends PNGs to Telegram. Run saved chart scripts with `./run-workspace-python.sh data/chart_name.py`. See `DATA_ANALYST.md` and your skill files for the template.
