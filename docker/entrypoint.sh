#!/bin/bash
# Docker entrypoint — provisions the 4-agent Brewlytics stack on first boot
# then starts the OpenClaw gateway.
#
# Agents:
#   main            → concierge (Telegram-bound, routes to specialists)
#   analyst         → descriptive BI
#   data-scientist  → forecasting, stats, anomalies
#   customer-intel  → loyalty, retention, segmentation
#
# One shared SQLite DB lives at ~/.openclaw/shared-data/starbucks_business.db
# and is symlinked into each specialist workspace.

set -e

OPENCLAW_DIR="${HOME}/.openclaw"
SHARED_DATA_DIR="${OPENCLAW_DIR}/shared-data"
SHARED_DB="${SHARED_DATA_DIR}/starbucks_business.db"

CONCIERGE_WS="${OPENCLAW_DIR}/workspace"            # default 'main' agent
ANALYST_WS="${OPENCLAW_DIR}/workspace-analyst"
DS_WS="${OPENCLAW_DIR}/workspace-ds"
CUSTOMER_WS="${OPENCLAW_DIR}/workspace-customer"

CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
APPROVALS_FILE="${OPENCLAW_DIR}/exec-approvals.json"
CONFIG_SRC="/opt/analyst/openclaw-config"

SQLITE3_PATH="$(which sqlite3)"
PYTHON3_PATH="$(which python3)"

# --- Validate required env ---
for var in TELEGRAM_BOT_TOKEN TELEGRAM_ALLOW_FROM; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is required"
        exit 1
    fi
done

PROVIDER="${OPENCLAW_PROVIDER:-}"
if [ -z "$PROVIDER" ]; then
    if [ -n "${VLLM_API_KEY:-}" ] || [[ "${OPENCLAW_MODEL:-}" == vllm/* ]]; then
        PROVIDER="vllm"
    else
        PROVIDER="openrouter"
    fi
fi

case "$PROVIDER" in
    openrouter)
        if [ -z "${OPENROUTER_API_KEY:-}" ]; then
            echo "ERROR: OPENROUTER_API_KEY is required when OPENCLAW_PROVIDER=openrouter"
            exit 1
        fi
        MODEL="${OPENCLAW_MODEL:-openrouter/x-ai/grok-3-fast}"
        ;;
    vllm)
        if [ -z "${OPENCLAW_MODEL:-}" ]; then
            echo "ERROR: OPENCLAW_MODEL is required for vLLM, e.g. vllm/meta-llama/Llama-3.1-8B-Instruct"
            exit 1
        fi
        if [[ "$OPENCLAW_MODEL" != vllm/* ]]; then
            echo "ERROR: vLLM models must use the vllm/<model-id> form"
            exit 1
        fi
        MODEL="$OPENCLAW_MODEL"
        export VLLM_API_KEY="${VLLM_API_KEY:-vllm-local}"
        export VLLM_BASE_URL="${VLLM_BASE_URL:-http://127.0.0.1:8000/v1}"
        export VLLM_CONTEXT_WINDOW="${VLLM_CONTEXT_WINDOW:-128000}"
        export VLLM_MAX_TOKENS="${VLLM_MAX_TOKENS:-8192}"
        ;;
    *)
        echo "ERROR: OPENCLAW_PROVIDER must be one of: openrouter, vllm"
        exit 1
        ;;
esac

# --- Generate openclaw.json if missing ---
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] No openclaw.json found — generating from environment..."

    python3 - "$CONFIG_FILE" "$PROVIDER" "$MODEL" "$CONCIERGE_WS" "$ANALYST_WS" "$DS_WS" "$CUSTOMER_WS" <<'PY'
import json
import os
import sys

config_file, provider, model, concierge_ws, analyst_ws, ds_ws, customer_ws = sys.argv[1:]
allow_from = [
    f"tg:{uid.strip()}"
    for uid in os.environ["TELEGRAM_ALLOW_FROM"].split(",")
    if uid.strip()
]
env = {}
models_config = None
if provider == "openrouter":
    env["OPENROUTER_API_KEY"] = os.environ["OPENROUTER_API_KEY"]
elif provider == "vllm":
    model_id = model.removeprefix("vllm/")
    env["VLLM_API_KEY"] = os.environ["VLLM_API_KEY"]
    models_config = {
        "mode": "merge",
        "providers": {
            "vllm": {
                "baseUrl": os.environ["VLLM_BASE_URL"],
                "apiKey": "${VLLM_API_KEY}",
                "api": "openai-completions",
                "models": [
                    {
                        "id": model_id,
                        "name": os.environ.get("VLLM_MODEL_NAME", model_id),
                        "reasoning": os.environ.get("VLLM_REASONING", "false").lower() == "true",
                        "input": ["text"],
                        "cost": {
                            "input": 0,
                            "output": 0,
                            "cacheRead": 0,
                            "cacheWrite": 0,
                        },
                        "contextWindow": int(os.environ["VLLM_CONTEXT_WINDOW"]),
                        "maxTokens": int(os.environ["VLLM_MAX_TOKENS"]),
                    },
                ],
            },
        },
    }
else:
    raise SystemExit(f"unsupported provider: {provider}")

config = {
    "env": env,
    "agents": {
        "defaults": {
            "model": model,
            "workspace": concierge_ws,
        },
        "analyst": {
            "model": model,
            "workspace": analyst_ws,
        },
        "data-scientist": {
            "model": model,
            "workspace": ds_ws,
        },
        "customer-intel": {
            "model": model,
            "workspace": customer_ws,
        },
    },
    "channels": {
        "telegram": {
            "botToken": os.environ["TELEGRAM_BOT_TOKEN"],
            "allowFrom": allow_from,
        },
    },
    "gateway": {
        "bind": "lan",
    },
}
if models_config:
    config["models"] = models_config
with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY
    echo "[entrypoint] Config created at $CONFIG_FILE"
else
    echo "[entrypoint] Config exists, skipping generation"
    echo "  NOTE: Changes to OPENCLAW_PROVIDER, OPENCLAW_MODEL, model credentials,"
    echo "  TELEGRAM_BOT_TOKEN, or TELEGRAM_ALLOW_FROM env vars will NOT take effect until the volume is reset."
    echo "  To reconfigure: docker compose down -v && docker compose up -d"
fi

# --- Also register specialists via the CLI (belt-and-suspenders with openclaw.json) ---
# If openclaw reads agents purely from openclaw.json this is a no-op; if it needs
# an explicit 'agents add', this covers it. Either way, second run is idempotent.
for entry in "analyst:${ANALYST_WS}" "data-scientist:${DS_WS}" "customer-intel:${CUSTOMER_WS}"; do
    name="${entry%%:*}"
    ws="${entry##*:}"
    if ! openclaw agents list 2>/dev/null | grep -q " $name "; then
        openclaw agents add "$name" --workspace "$ws" --model "$MODEL" 2>/dev/null \
            && echo "[entrypoint] Registered agent '$name'" \
            || echo "[entrypoint] 'openclaw agents add $name' failed (may already exist)"
    fi
done

# --- Per-agent exec approvals ---
# Concierge gets ONLY the specialist invoker wrapper. No raw openclaw, no sqlite3,
# no python3 — concierge doesn't analyze, it routes.
# Specialists get sqlite3 + python3 + their own data/python3 symlink.
if [ ! -f "$APPROVALS_FILE" ]; then
    echo "[entrypoint] Creating per-agent exec-approvals.json..."
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
        { "pattern": "${CONCIERGE_WS}/invoke-specialist.sh" }
      ]
    },
    "analyst": {
      "security": "allowlist",
      "ask": "off",
      "askFallback": "deny",
      "autoAllowSkills": true,
      "allowlist": [
        { "pattern": "${SQLITE3_PATH}" },
        { "pattern": "${PYTHON3_PATH}" },
        { "pattern": "${ANALYST_WS}/data/python3" }
      ]
    },
    "data-scientist": {
      "security": "allowlist",
      "ask": "off",
      "askFallback": "deny",
      "autoAllowSkills": true,
      "allowlist": [
        { "pattern": "${SQLITE3_PATH}" },
        { "pattern": "${PYTHON3_PATH}" },
        { "pattern": "${DS_WS}/data/python3" }
      ]
    },
    "customer-intel": {
      "security": "allowlist",
      "ask": "off",
      "askFallback": "deny",
      "autoAllowSkills": true,
      "allowlist": [
        { "pattern": "${SQLITE3_PATH}" },
        { "pattern": "${PYTHON3_PATH}" },
        { "pattern": "${CUSTOMER_WS}/data/python3" }
      ]
    }
  }
}
EOF
    echo "[entrypoint] Approvals written"
else
    echo "[entrypoint] Exec approvals exist, skipping creation"
fi

# --- Generate shared DB if missing ---
mkdir -p "$SHARED_DATA_DIR"
if [ ! -f "$SHARED_DB" ]; then
    echo "[entrypoint] Generating Starbucks database..."
    # Generator writes to ~/.openclaw/workspace/data/ by default; we move it.
    mkdir -p "$CONCIERGE_WS/data"
    python3 /opt/analyst/generate_starbucks_db.py
    mv "$CONCIERGE_WS/data/starbucks_business.db" "$SHARED_DB"
    # Clean up the empty data/ dir — concierge doesn't need one.
    rmdir "$CONCIERGE_WS/data" 2>/dev/null || true
    echo "[entrypoint] DB at $SHARED_DB"
else
    echo "[entrypoint] DB exists, skipping generation"
fi

# --- Concierge workspace (the 'main' agent) ---
# No DB, no DATA_ANALYST.md, no skills — just routing + persona + memory rules.
echo "[entrypoint] Installing concierge workspace..."
mkdir -p "$CONCIERGE_WS/memory"
cp "$CONFIG_SRC/shared/BRAND.md"                       "$CONCIERGE_WS/BRAND.md"
cp "$CONFIG_SRC/shared/MEMORY_RULES.md"                "$CONCIERGE_WS/MEMORY_RULES.md"
cp "$CONFIG_SRC/agents/concierge/SOUL.md"              "$CONCIERGE_WS/SOUL.md"
cp "$CONFIG_SRC/agents/concierge/AGENTS.md"            "$CONCIERGE_WS/AGENTS.md"
cp "$CONFIG_SRC/agents/concierge/ROUTING.md"           "$CONCIERGE_WS/ROUTING.md"
cp "$CONFIG_SRC/agents/concierge/GROUP_CHAT.md"        "$CONCIERGE_WS/GROUP_CHAT.md"
cp "$CONFIG_SRC/agents/concierge/HEARTBEAT_GUIDE.md"   "$CONCIERGE_WS/HEARTBEAT_GUIDE.md"
cp "$CONFIG_SRC/shared/invoke-specialist.sh"           "$CONCIERGE_WS/invoke-specialist.sh"
chmod +x "$CONCIERGE_WS/invoke-specialist.sh"

# --- Specialist workspace installer ---
install_specialist() {
    local agent_dir="$1"
    local workspace="$2"
    local extra_file="$3"  # optional, e.g. TECHNICAL_SKILLS.md

    mkdir -p "$workspace/data" "$workspace/memory"

    # Shared files (BRAND, DATA_ANALYST, MEMORY_RULES, SCHEMA, chart helpers)
    cp "$CONFIG_SRC/shared/BRAND.md"            "$workspace/BRAND.md"
    cp "$CONFIG_SRC/shared/DATA_ANALYST.md"     "$workspace/DATA_ANALYST.md"
    cp "$CONFIG_SRC/shared/MEMORY_RULES.md"     "$workspace/MEMORY_RULES.md"
    cp "$CONFIG_SRC/shared/data/SCHEMA.md"      "$workspace/data/SCHEMA.md"
    cp "$CONFIG_SRC/shared/data/brew_chart.py"  "$workspace/data/brew_chart.py"
    cp "$CONFIG_SRC/shared/data/send_photo.py"  "$workspace/data/send_photo.py"

    # Agent-specific
    cp "$CONFIG_SRC/agents/$agent_dir/SOUL.md"   "$workspace/SOUL.md"
    cp "$CONFIG_SRC/agents/$agent_dir/AGENTS.md" "$workspace/AGENTS.md"

    if [ -n "$extra_file" ]; then
        cp "$CONFIG_SRC/agents/$agent_dir/$extra_file" "$workspace/$extra_file"
    fi

    # Skills — wipe + copy so removed skills actually go away
    rm -rf "$workspace/skills"
    cp -r "$CONFIG_SRC/agents/$agent_dir/skills" "$workspace/skills"

    # Symlink the shared DB + python3 into the workspace
    ln -sf "$SHARED_DB"     "$workspace/data/starbucks_business.db"
    ln -sf "$PYTHON3_PATH"  "$workspace/data/python3"
}

echo "[entrypoint] Installing specialist workspaces..."
install_specialist "analyst"        "$ANALYST_WS"   ""
install_specialist "data-scientist" "$DS_WS"        "TECHNICAL_SKILLS.md"
install_specialist "customer-intel" "$CUSTOMER_WS"  ""

echo "[entrypoint] Setup complete. Starting gateway..."
exec node dist/index.js gateway run
