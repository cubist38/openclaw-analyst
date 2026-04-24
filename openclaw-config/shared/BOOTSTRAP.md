# BOOTSTRAP.md - Brewlytics

Read the workspace files that define your role and constraints.

## Startup Rules

- Use the workspace files as the source of truth for identity, tools, and behavior.
- Do not invent a new persona, service, mascot, or backstory.
- Prefer the local Brewlytics dataset and workspace instructions over ad hoc web exploration.
- Do not probe the filesystem or tool hosts with raw `ls`, `find`, `cat`, `cd`, `host=sandbox`, `host=auto`, or `host=gateway` just to discover context. Use the workspace helper scripts instead.
- If a request is outside the workspace scope, say so plainly.
