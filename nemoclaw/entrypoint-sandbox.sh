#!/bin/bash
# First-boot provisioning for Brewlytics inside a NemoClaw sandbox.
#
# Runs as user `sandbox`. /sandbox/.openclaw is Landlock-read-only, so we write
# everything to /sandbox/.openclaw-data/ — symlinks in the immutable dir (baked
# by Dockerfile.sandbox) route OpenClaw reads through to these writable targets.
#
# On first boot:
#   1. Generate openclaw.json from env vars (OPENROUTER_API_KEY, NVIDIA_API_KEY,
#      or VLLM_API_KEY,
#      TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOW_FROM)
#   2. Generate per-agent exec-approvals.json
#   3. Assemble 4 workspaces (concierge + 3 specialists) under workspaces/
#   4. Generate the shared SQLite DB and symlink it into each specialist
#
# On subsequent boots: everything exists, we just launch the gateway.

set -e

DATA=/sandbox/.openclaw-data
CONFIG_FILE=$DATA/openclaw.json
APPROVALS_FILE=$DATA/exec-approvals.json

SHARED_DATA=$DATA/shared-data
SHARED_DB=$SHARED_DATA/starbucks_business.db

WS_CONCIERGE=$DATA/workspaces/main
WS_ANALYST=$DATA/workspaces/analyst
WS_DS=$DATA/workspaces/data-scientist
WS_CUSTOMER=$DATA/workspaces/customer-intel

CONFIG_SRC=/app/openclaw-config
SQLITE3_PATH=$(command -v sqlite3)
PYTHON3_PATH=$(command -v python3)

# --- Select inference provider ----------------------------------------------
# Blueprint profile picks this; we mirror the env vars NemoClaw's onboard
# wizard sets, then fall back to OPENROUTER_API_KEY or VLLM_API_KEY.
if [ -n "${NVIDIA_API_KEY:-}" ]; then
    INFERENCE_PROVIDER="nvidia"
    INFERENCE_ENV_KEY="NVIDIA_API_KEY"
    INFERENCE_ENV_VALUE="${NVIDIA_API_KEY}"
    MODEL="${OPENCLAW_MODEL:-nvidia/nemotron-3-super-120b-a12b}"
elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
    INFERENCE_PROVIDER="openrouter"
    INFERENCE_ENV_KEY="OPENROUTER_API_KEY"
    INFERENCE_ENV_VALUE="${OPENROUTER_API_KEY}"
    MODEL="${OPENCLAW_MODEL:-openrouter/x-ai/grok-3-fast}"
elif [ -n "${VLLM_API_KEY:-}" ]; then
    INFERENCE_PROVIDER="vllm"
    INFERENCE_ENV_KEY="VLLM_API_KEY"
    INFERENCE_ENV_VALUE="${VLLM_API_KEY}"
    MODEL="${OPENCLAW_MODEL:-}"
    if [ -z "$MODEL" ]; then
        echo "ERROR: OPENCLAW_MODEL is required for vLLM, e.g. vllm/meta-llama/Llama-3.1-8B-Instruct"
        exit 1
    fi
    if [[ "$MODEL" != vllm/* ]]; then
        echo "ERROR: vLLM models must use the vllm/<model-id> form"
        exit 1
    fi
    export VLLM_BASE_URL="${VLLM_BASE_URL:-http://vllm.local:8000/v1}"
    export VLLM_CONTEXT_WINDOW="${VLLM_CONTEXT_WINDOW:-128000}"
    export VLLM_MAX_TOKENS="${VLLM_MAX_TOKENS:-8192}"
else
    echo "ERROR: one of NVIDIA_API_KEY, OPENROUTER_API_KEY, or VLLM_API_KEY must be set"
    exit 1
fi

for var in TELEGRAM_BOT_TOKEN TELEGRAM_ALLOW_FROM; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: $var is required"
        exit 1
    fi
done

mkdir -p "$DATA" "$SHARED_DATA" "$DATA/workspaces"

# --- openclaw.json (writable target of the immutable symlink) ---------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[nemoclaw-entrypoint] Generating openclaw.json..."

    python3 - "$CONFIG_FILE" "$INFERENCE_PROVIDER" "$MODEL" "$INFERENCE_ENV_KEY" "$INFERENCE_ENV_VALUE" "$WS_CONCIERGE" "$WS_ANALYST" "$WS_DS" "$WS_CUSTOMER" <<'PY'
import json
import os
import sys

(
    config_file,
    provider,
    model,
    inference_env_key,
    inference_env_value,
    concierge_ws,
    analyst_ws,
    ds_ws,
    customer_ws,
) = sys.argv[1:]
allow_from = [
    f"tg:{uid.strip()}"
    for uid in os.environ["TELEGRAM_ALLOW_FROM"].split(",")
    if uid.strip()
]
env = {
    inference_env_key: inference_env_value,
}
models_config = None
if provider == "vllm":
    model_id = model.removeprefix("vllm/")
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
config = {
    "env": env,
    "agents": {
        "defaults": {
            "model": model,
            "workspace": concierge_ws,
        },
        "list": [
            {
                "id": "main",
                "default": True,
                "name": "concierge",
                "workspace": concierge_ws,
                "model": model,
            },
            {
                "id": "analyst",
                "name": "analyst",
                "workspace": analyst_ws,
                "model": model,
            },
            {
                "id": "data-scientist",
                "name": "data-scientist",
                "workspace": ds_ws,
                "model": model,
            },
            {
                "id": "customer-intel",
                "name": "customer-intel",
                "workspace": customer_ws,
                "model": model,
            },
        ],
    },
    "channels": {
        "telegram": {
            "botToken": os.environ["TELEGRAM_BOT_TOKEN"],
            "allowFrom": allow_from,
        },
    },
    "gateway": {
        "mode": "local",
        "bind": "lan",
        "port": 18789,
    },
}
if models_config:
    config["models"] = models_config
with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY
    chmod 600 "$CONFIG_FILE"
fi

# --- exec-approvals.json ----------------------------------------------------
if [ ! -f "$APPROVALS_FILE" ]; then
    echo "[nemoclaw-entrypoint] Generating exec-approvals.json..."
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
      "security": "allowlist", "ask": "off", "askFallback": "deny",
      "autoAllowSkills": true,
      "allowlist": [
        { "pattern": "${WS_CONCIERGE}/invoke-specialist.sh" }
      ]
    },
    "analyst": {
      "security": "allowlist", "ask": "off", "askFallback": "deny",
      "autoAllowSkills": true,
      "allowlist": [
        { "pattern": "${SQLITE3_PATH}" },
        { "pattern": "${PYTHON3_PATH}" },
        { "pattern": "${WS_ANALYST}/data/python3" }
      ]
    },
    "data-scientist": {
      "security": "allowlist", "ask": "off", "askFallback": "deny",
      "autoAllowSkills": true,
      "allowlist": [
        { "pattern": "${SQLITE3_PATH}" },
        { "pattern": "${PYTHON3_PATH}" },
        { "pattern": "${WS_DS}/data/python3" }
      ]
    },
    "customer-intel": {
      "security": "allowlist", "ask": "off", "askFallback": "deny",
      "autoAllowSkills": true,
      "allowlist": [
        { "pattern": "${SQLITE3_PATH}" },
        { "pattern": "${PYTHON3_PATH}" },
        { "pattern": "${WS_CUSTOMER}/data/python3" }
      ]
    }
  }
}
EOF
    chmod 600 "$APPROVALS_FILE"
fi

# --- Shared DB --------------------------------------------------------------
if [ ! -f "$SHARED_DB" ]; then
    echo "[nemoclaw-entrypoint] Generating Starbucks DB..."
    # Generator writes to ~/.openclaw/workspace/data/; we relocate.
    # Inside the sandbox, HOME is /sandbox and that default path is Landlock-
    # restricted, so we override the config's db_path via a side-car temp dir.
    tmpdir=$(mktemp -d)
    (cd /app && \
        HOME="$tmpdir" python3 /app/generate_starbucks_db.py) || {
            echo "ERROR: DB generation failed"; exit 1;
        }
    mv "$tmpdir/.openclaw/workspace/data/starbucks_business.db" "$SHARED_DB"
    rm -rf "$tmpdir"
fi

# --- Workspace assembly (per agent) ----------------------------------------
install_specialist() {
    local agent_dir="$1"   # concierge | analyst | data-scientist | customer-intel
    local ws="$2"
    local extra_file="$3"  # optional, e.g. TECHNICAL_SKILLS.md

    mkdir -p "$ws/memory"

    cp "$CONFIG_SRC/shared/BRAND.md"          "$ws/BRAND.md"
    cp "$CONFIG_SRC/shared/MEMORY_RULES.md"   "$ws/MEMORY_RULES.md"
    cp "$CONFIG_SRC/agents/$agent_dir/SOUL.md" "$ws/SOUL.md"
    cp "$CONFIG_SRC/agents/$agent_dir/AGENTS.md" "$ws/AGENTS.md"

    # Specialist-only: DATA_ANALYST.md + schema + chart helpers + DB + python3
    if [ "$agent_dir" != "concierge" ]; then
        mkdir -p "$ws/data"
        cp "$CONFIG_SRC/shared/DATA_ANALYST.md"     "$ws/DATA_ANALYST.md"
        cp "$CONFIG_SRC/shared/data/SCHEMA.md"      "$ws/data/SCHEMA.md"
        cp "$CONFIG_SRC/shared/data/brew_chart.py"  "$ws/data/brew_chart.py"
        cp "$CONFIG_SRC/shared/data/send_photo.py"  "$ws/data/send_photo.py"
        ln -sf "$SHARED_DB"     "$ws/data/starbucks_business.db"
        ln -sf "$PYTHON3_PATH"  "$ws/data/python3"

        if [ -d "$CONFIG_SRC/agents/$agent_dir/skills" ]; then
            rm -rf "$ws/skills"
            cp -r "$CONFIG_SRC/agents/$agent_dir/skills" "$ws/skills"
        fi
    fi

    if [ -n "$extra_file" ]; then
        cp "$CONFIG_SRC/agents/$agent_dir/$extra_file" "$ws/$extra_file"
    fi
}

# Concierge: no DB, no DATA_ANALYST.md, no skills — just routing
if [ ! -f "$WS_CONCIERGE/SOUL.md" ]; then
    echo "[nemoclaw-entrypoint] Installing concierge workspace..."
    install_specialist "concierge" "$WS_CONCIERGE" ""
    cp "$CONFIG_SRC/agents/concierge/ROUTING.md"          "$WS_CONCIERGE/ROUTING.md"
    cp "$CONFIG_SRC/agents/concierge/GROUP_CHAT.md"       "$WS_CONCIERGE/GROUP_CHAT.md"
    cp "$CONFIG_SRC/agents/concierge/HEARTBEAT_GUIDE.md"  "$WS_CONCIERGE/HEARTBEAT_GUIDE.md"
    cp "$CONFIG_SRC/shared/invoke-specialist.sh"          "$WS_CONCIERGE/invoke-specialist.sh"
    chmod +x "$WS_CONCIERGE/invoke-specialist.sh"
fi

# Specialists
if [ ! -f "$WS_ANALYST/SOUL.md" ]; then
    echo "[nemoclaw-entrypoint] Installing analyst workspace..."
    install_specialist "analyst"        "$WS_ANALYST"   ""
fi
if [ ! -f "$WS_DS/SOUL.md" ]; then
    echo "[nemoclaw-entrypoint] Installing data-scientist workspace..."
    install_specialist "data-scientist" "$WS_DS"        "TECHNICAL_SKILLS.md"
fi
if [ ! -f "$WS_CUSTOMER/SOUL.md" ]; then
    echo "[nemoclaw-entrypoint] Installing customer-intel workspace..."
    install_specialist "customer-intel" "$WS_CUSTOMER"  ""
fi

echo "[nemoclaw-entrypoint] Ready. Launching gateway..."
exec openclaw gateway run
