#!/bin/bash
set -e

OPENCLAW_DIR="${HOME}/.openclaw"
WORKSPACE="${OPENCLAW_DIR}/workspace"
CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
APPROVALS_FILE="${OPENCLAW_DIR}/exec-approvals.json"

# --- Generate openclaw.json if missing ---
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] No openclaw.json found — generating from environment..."

    if [ -z "$OPENROUTER_API_KEY" ]; then
        echo "ERROR: OPENROUTER_API_KEY is required"
        exit 1
    fi
    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        echo "ERROR: TELEGRAM_BOT_TOKEN is required"
        exit 1
    fi
    if [ -z "$TELEGRAM_ALLOW_FROM" ]; then
        echo "ERROR: TELEGRAM_ALLOW_FROM is required (comma-separated numeric user IDs)"
        exit 1
    fi

    # Build allowFrom array from comma-separated IDs
    ALLOW_JSON=$(python3 -c "
import os, json
ids = [f'tg:{uid.strip()}' for uid in os.environ['TELEGRAM_ALLOW_FROM'].split(',') if uid.strip()]
print(json.dumps(ids))
")

    MODEL="${OPENCLAW_MODEL:-openrouter/x-ai/grok-3-fast}"

    cat > "$CONFIG_FILE" << EOF
{
  "env": {
    "OPENROUTER_API_KEY": "${OPENROUTER_API_KEY}"
  },
  "agents": {
    "defaults": {
      "model": "${MODEL}",
      "workspace": "${WORKSPACE}"
    }
  },
  "channels": {
    "telegram": {
      "botToken": "${TELEGRAM_BOT_TOKEN}",
      "allowFrom": ${ALLOW_JSON}
    }
  },
  "gateway": {
    "bind": "lan"
  }
}
EOF
    echo "[entrypoint] Config created at $CONFIG_FILE"
else
    echo "[entrypoint] Config exists, skipping generation"
    echo "  To reconfigure: delete the volume or edit via Control UI at http://localhost:18789"
fi

# --- Set up exec approvals for sqlite3 ---
SQLITE3_PATH="$(which sqlite3)"
if [ ! -f "$APPROVALS_FILE" ]; then
    echo "[entrypoint] Creating exec-approvals.json with sqlite3 allowlisted..."
    cat > "$APPROVALS_FILE" << EOF
{
  "version": 1,
  "defaults": {
    "security": "allowlist",
    "ask": "off",
    "askFallback": "deny"
  },
  "agents": {
    "main": {
      "security": "allowlist",
      "ask": "off",
      "askFallback": "deny",
      "autoAllowSkills": true,
      "allowlist": [
        {
          "pattern": "${SQLITE3_PATH}"
        }
      ]
    }
  }
}
EOF
    echo "[entrypoint] Allowlisted: $SQLITE3_PATH"
else
    echo "[entrypoint] Exec approvals exist, skipping creation"
fi

# --- Copy workspace files (always overwrite to stay in sync) ---
echo "[entrypoint] Setting up workspace files..."
mkdir -p "$WORKSPACE/data" "$WORKSPACE/skills" "$WORKSPACE/memory"

cp /opt/analyst/openclaw-config/SOUL.md "$WORKSPACE/SOUL.md"
cp /opt/analyst/openclaw-config/DATA_ANALYST.md "$WORKSPACE/DATA_ANALYST.md"
cp /opt/analyst/openclaw-config/AGENTS.md "$WORKSPACE/AGENTS.md"
cp /opt/analyst/openclaw-config/MEMORY_RULES.md "$WORKSPACE/MEMORY_RULES.md"
cp /opt/analyst/openclaw-config/GROUP_CHAT.md "$WORKSPACE/GROUP_CHAT.md"
cp /opt/analyst/openclaw-config/HEARTBEAT_GUIDE.md "$WORKSPACE/HEARTBEAT_GUIDE.md"
cp -r /opt/analyst/openclaw-config/skills/* "$WORKSPACE/skills/"
cp /opt/analyst/openclaw-config/data/SCHEMA.md "$WORKSPACE/data/SCHEMA.md"

# --- Generate database if missing ---
DB_FILE="$WORKSPACE/data/starbucks_business.db"
if [ ! -f "$DB_FILE" ]; then
    echo "[entrypoint] Generating Starbucks database..."
    python3 /opt/analyst/generate_starbucks_db.py
else
    echo "[entrypoint] Database exists, skipping generation"
fi

echo "[entrypoint] Setup complete. Starting gateway..."
exec node dist/index.js gateway run
