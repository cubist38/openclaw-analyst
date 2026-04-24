#!/bin/bash
# run-workspace-python.sh — execute a workspace-local Python script without cd wrappers.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: run-workspace-python.sh <relative-script-path> [args...]" >&2
  exit 2
fi

SCRIPT_REL="${1#./}"
shift

case "$SCRIPT_REL" in
  data/*.py)
    ;;
  *)
    echo "ERROR: '$SCRIPT_REL' must be a Python script under data/" >&2
    exit 3
    ;;
esac

case "$SCRIPT_REL" in
  ../*|*/../*|*/..)
    echo "ERROR: path traversal is not allowed" >&2
    exit 3
    ;;
esac

WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_BIN="$WORKSPACE_DIR/data/python3"
SCRIPT_PATH="$WORKSPACE_DIR/$SCRIPT_REL"

if [ ! -x "$PYTHON_BIN" ]; then
  echo "ERROR: python runner not found at data/python3" >&2
  exit 4
fi

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "ERROR: '$SCRIPT_REL' does not exist in this workspace" >&2
  exit 4
fi

cd "$WORKSPACE_DIR"
# Merge stderr into stdout so the caller sees tracebacks and warnings without
# having to tack on `2>&1`, which is easy for agents to get wrong and can be
# blocked by stricter OpenClaw security modes.
exec "$PYTHON_BIN" "$SCRIPT_PATH" "$@" 2>&1
