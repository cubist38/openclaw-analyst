#!/bin/bash
# invoke-specialist.sh — secure wrapper the concierge uses to call a specialist.
#
# Only allows invoking the 3 named specialists with --local. Any other
# openclaw subcommand (agents add, approvals, etc.) is blocked, so a
# compromised concierge cannot escalate privileges via the openclaw CLI.
#
# Usage:
#   invoke-specialist.sh <analyst|data-scientist|customer-intel> <session-id> <message...>

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: invoke-specialist.sh <analyst|data-scientist|customer-intel> <session-id> <message...>" >&2
  exit 2
fi

AGENT="$1"
SESSION="$2"
shift 2
MESSAGE="$*"

case "$AGENT" in
  analyst|data-scientist|customer-intel) ;;
  *)
    echo "ERROR: '$AGENT' is not a known specialist. Allowed: analyst, data-scientist, customer-intel" >&2
    exit 3
    ;;
esac

exec openclaw agent --agent "$AGENT" --local --session-id "$SESSION" -m "$MESSAGE"
