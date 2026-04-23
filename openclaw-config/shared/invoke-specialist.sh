#!/bin/bash
# invoke-specialist.sh — secure wrapper the concierge uses to call a specialist.
#
# Only allows invoking the 3 named specialists with --local. Any other
# openclaw subcommand (agents add, approvals, etc.) is blocked, so a
# compromised concierge cannot escalate privileges via the openclaw CLI.
#
# Usage:
#   invoke-specialist.sh <analyst|data-scientist|customer-intel> <session-id> <message...>
#   invoke-specialist.sh <analyst|data-scientist|customer-intel> <message>

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: invoke-specialist.sh <analyst|data-scientist|customer-intel> [session-id] <message...>" >&2
  exit 2
fi

AGENT="$1"
shift

case "$AGENT" in
  analyst|data-scientist|customer-intel) ;;
  *)
    echo "ERROR: '$AGENT' is not a known specialist. Allowed: analyst, data-scientist, customer-intel" >&2
    exit 3
    ;;
esac

SESSION=""
case "${1:-}" in
  tg:[0-9]*|telegram:[0-9]*|[0-9]*|-|stateless)
    SESSION="$1"
    shift
    ;;
esac
MESSAGE="$*"

if [ -z "$MESSAGE" ]; then
  echo "ERROR: message cannot be empty" >&2
  exit 2
fi

# If OpenClaw uses Telegram-flavored session IDs, pass the chat through to
# chart helpers so generated images only go back to the requesting chat.
case "$SESSION" in
  tg:[0-9]*)
    export BREWLYTICS_TELEGRAM_CHAT_ID="${SESSION#tg:}"
    ;;
  telegram:[0-9]*)
    export BREWLYTICS_TELEGRAM_CHAT_ID="${SESSION#telegram:}"
    ;;
  [0-9]*)
    export BREWLYTICS_TELEGRAM_CHAT_ID="$SESSION"
    ;;
esac

if [ -n "$SESSION" ] && [ "$SESSION" != "-" ] && [ "$SESSION" != "stateless" ]; then
  exec openclaw agent --agent "$AGENT" --local --session-id "$SESSION" -m "$MESSAGE"
fi

exec openclaw agent --agent "$AGENT" --local -m "$MESSAGE"
