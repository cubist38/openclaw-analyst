#!/bin/bash
# read-workspace-file.sh — read-only helper for workspace prompt/memory files.
#
# Accepts one or more relative paths. Multiple files are concatenated with a
# `--- <path> ---` header before each so the agent can read today + yesterday
# memory in a single call instead of reaching for compound shell commands.

set -euo pipefail

# Mirror stderr onto stdout so the caller sees validation errors without
# needing `2>&1`, which is easy for agents to get wrong and can be blocked by
# stricter OpenClaw security modes.
exec 2>&1

if [ "$#" -lt 1 ]; then
  echo "Usage: read-workspace-file.sh <relative-path> [<relative-path> ...]"
  exit 2
fi

WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"

validate_target() {
  local target="$1"
  case "$target" in
    SOUL.md|BRAND.md|ROUTING.md|MEMORY_RULES.md|MEMORY.md|GROUP_CHAT.md|HEARTBEAT_GUIDE.md|HEARTBEAT.md|BOOTSTRAP.md|TOOLS.md|DATA_ANALYST.md|TECHNICAL_SKILLS.md|IDENTITY.md|USER.md|AGENTS.md|data/SCHEMA.md|memory/heartbeat-state.json|memory/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md|skills/*/SKILL.md)
      ;;
    *)
      echo "ERROR: '$target' is not an allowed workspace file" >&2
      exit 3
      ;;
  esac

  case "$target" in
    ../*|*/../*|*/..)
      echo "ERROR: path traversal is not allowed" >&2
      exit 3
      ;;
  esac
}

# Dated memory files are created lazily (the seeder only runs at boot), so a
# missing memory/YYYY-MM-DD.md is an expected state after midnight — treat as
# empty rather than erroring. Any other missing file is a real error.
is_dated_memory() {
  case "$1" in
    memory/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) return 0 ;;
    *) return 1 ;;
  esac
}

multi=0
if [ "$#" -gt 1 ]; then
  multi=1
fi

for raw in "$@"; do
  target="${raw#./}"
  validate_target "$target"
  file_path="$WORKSPACE_DIR/$target"

  if [ "$multi" -eq 1 ]; then
    printf -- '--- %s ---\n' "$target"
  fi

  if [ ! -f "$file_path" ]; then
    if is_dated_memory "$target"; then
      continue
    fi
    echo "ERROR: '$target' does not exist in this workspace" >&2
    exit 4
  fi

  cat -- "$file_path"
done
