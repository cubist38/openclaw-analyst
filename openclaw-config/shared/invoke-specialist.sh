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
  # Keep the chat-id in the specialist session id so memory reads use the
  # right per-chat files. Sanitize filesystem-unsafe chars like ":".
  #
  # Note: openclaw keys sessions by `agent:<name>:<caller>` and reuses the
  # first session across calls from the same caller regardless of --session-id,
  # so this id is effectively cosmetic. Passing it anyway is harmless and
  # leaves a breadcrumb in sessions.json.
  SPECIALIST_SESSION="$(printf '%s' "${AGENT}--${SESSION}" | tr ':/' '__')"
fi

# Per-agent serialization. openclaw already serializes agent:<name>:<caller>
# pairs internally, but it surfaces concurrent invocations as a generic
# "session file locked (timeout …)" error that the concierge model tends to
# interpret as "something is broken, retry harder" — including trying to
# `kill` the running specialist. Fail fast with a clear message instead, so
# the concierge relays "already working" to the user and the in-flight call
# finishes without getting murdered.
LOCK_DIR="${HOME}/.openclaw/locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/${AGENT}.lock"
LOCK_FALLBACK_DIR="${LOCK_FILE}.d"
LOCK_MODE="flock"

if command -v flock >/dev/null 2>&1; then
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    echo "BUSY: a ${AGENT} request is already in progress. Wait for it to finish before retrying — do not kill or re-invoke." >&2
    exit 7
  fi
elif mkdir "$LOCK_FALLBACK_DIR" 2>/dev/null; then
  LOCK_MODE="mkdir"
  trap 'rmdir "$LOCK_FALLBACK_DIR" 2>/dev/null || true' EXIT INT TERM
else
  echo "BUSY: a ${AGENT} request is already in progress. Wait for it to finish before retrying — do not kill or re-invoke." >&2
  exit 7
fi

if [ -n "${SPECIALIST_SESSION:-}" ]; then
  if [ "$LOCK_MODE" = "flock" ]; then
    exec openclaw agent --agent "$AGENT" --local --session-id "$SPECIALIST_SESSION" -m "$MESSAGE"
  fi
  openclaw agent --agent "$AGENT" --local --session-id "$SPECIALIST_SESSION" -m "$MESSAGE"
  exit $?
fi

if [ "$LOCK_MODE" = "flock" ]; then
  exec openclaw agent --agent "$AGENT" --local -m "$MESSAGE"
fi
openclaw agent --agent "$AGENT" --local -m "$MESSAGE"
