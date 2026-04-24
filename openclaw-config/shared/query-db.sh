#!/bin/bash
# query-db.sh — run read-only MySQL queries against the Brewlytics database.

set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS_FILE="${WORKSPACE_DIR}/data/mysql-readonly.cnf"

if [ ! -f "$DEFAULTS_FILE" ]; then
  echo "ERROR: MySQL read-only config not found at data/mysql-readonly.cnf" >&2
  exit 4
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: query-db.sh <SQL>" >&2
  exit 2
fi

sql="$*"
first_word="$(printf '%s' "$sql" | sed 's/^[[:space:]]*//' | awk '{print toupper($1)}')"
case "$first_word" in
  SELECT|WITH|SHOW|DESCRIBE|EXPLAIN) ;;
  *)
    echo "ERROR: query-db.sh only accepts read-only statements; the MySQL user is SELECT-only." >&2
    exit 3
    ;;
esac

exec mysql --defaults-extra-file="$DEFAULTS_FILE" --table --execute="$sql"
