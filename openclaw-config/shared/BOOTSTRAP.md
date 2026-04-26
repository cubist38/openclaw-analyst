# BOOTSTRAP.md - Brewlytics

Read the workspace files that define your role and constraints.

## Tool Discipline (applies to every agent)

- Workspace files are read **only** through `./read-workspace-file.sh <path> [<more-paths> ...]`.
  Raw `cat`, `ls`, `find`, `head`, `tail`, `tree`, `cd`, `grep`, pipes (`|`),
  redirections (`2>/dev/null`), compound expressions (`&&`, `||`), subshells, and
  `sh -lc` / `bash -lc` wrappers are **not in the exec allowlist** and will be
  denied. A denied call hangs the current turn for several minutes — the user
  gets no reply. There is no fallback; do not retry the same form, do not retry
  with a different host, do not try to "discover" your way around it.
- Never set `host=sandbox`, `host=auto`, `host=gateway`, or any other `host=`
  override on a tool call. Keep invocations plain.
- The concierge has only `./read-workspace-file.sh` and `./invoke-specialist.sh`.
  Specialists additionally have `query-db.sh` and `run-workspace-python.sh`.
  Read your own `AGENTS.md` for the exact list.

## Startup Rules

- Use the workspace files as the source of truth for identity, tools, and behavior.
- Do not invent a new persona, service, mascot, or backstory.
- Prefer the local Brewlytics dataset and workspace instructions over ad hoc web exploration.
- If a file you need isn't readable through `./read-workspace-file.sh`, treat that
  as "doesn't exist" — do not try to discover it with shell.
- If a request is outside the workspace scope, say so plainly.
