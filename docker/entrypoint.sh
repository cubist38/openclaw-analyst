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
# One shared MySQL database lives in the docker-compose mysql service. It is
# initialized from database/init before this service starts. Specialists query
# through a SELECT-only user.

set -e

OPENCLAW_DIR="${HOME}/.openclaw"
CONCIERGE_WS="${OPENCLAW_DIR}/workspace"            # default 'main' agent
ANALYST_WS="${OPENCLAW_DIR}/workspace-analyst"
DS_WS="${OPENCLAW_DIR}/workspace-ds"
CUSTOMER_WS="${OPENCLAW_DIR}/workspace-customer"

CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
APPROVALS_FILE="${OPENCLAW_DIR}/exec-approvals.json"
CONFIG_SRC="/opt/analyst/openclaw-config"

MYSQL_HOST="${MYSQL_HOST:-mysql}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_DATABASE="${MYSQL_DATABASE:-brewlytics}"
MYSQL_READONLY_USER="${MYSQL_READONLY_USER:-brewlytics_ro}"
MYSQL_READONLY_PASSWORD="${MYSQL_READONLY_PASSWORD:-brewlytics_readonly_change_me}"

if [ "$(id -u)" = "0" ]; then
    mkdir -p /home/node/.openclaw
    chown -R node:node /home/node/.openclaw
    export HOME=/home/node
    exec su -p node -s /bin/bash -c 'exec /opt/analyst/entrypoint.sh --as-node'
fi

PYTHON3_PATH="$(which python3)"

write_mysql_readonly_config() {
    local workspace="$1"
    local cnf="$workspace/data/mysql-readonly.cnf"

    umask 077
    cat > "$cnf" <<EOF
[client]
host=${MYSQL_HOST}
port=${MYSQL_PORT}
user=${MYSQL_READONLY_USER}
password=${MYSQL_READONLY_PASSWORD}
database=${MYSQL_DATABASE}
protocol=TCP
default-character-set=utf8mb4
EOF
    chmod 600 "$cnf"
}

seed_memory_files() {
    local workspace="$1"

    mkdir -p "$workspace/memory"
    touch "$workspace/MEMORY.md"

    for day in $(python3 -c 'from datetime import date, timedelta; today = date.today(); print(today.isoformat()); print((today - timedelta(days=1)).isoformat())'); do
        touch "$workspace/memory/$day.md"
    done
}

render_routing_md() {
    local target="$1"
    local invoke_path="$2"

    python3 - "$CONFIG_SRC/agents/concierge/ROUTING.md" "$target" "$invoke_path" <<'PY'
import pathlib
import sys

src, dst, invoke_path = sys.argv[1:]
text = pathlib.Path(src).read_text()
text = text.replace("__INVOKE_SPECIALIST_PATH__", invoke_path)
pathlib.Path(dst).write_text(text)
PY
}

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
allow_from = []
groups = {}
for raw in os.environ["TELEGRAM_ALLOW_FROM"].split(","):
    entry = raw.strip()
    if not entry:
        continue
    if entry.startswith(("tg:", "telegram:")):
        entry = entry.split(":", 1)[1].strip()
    if entry == "*":
        allow_from.append(entry)
    elif entry.startswith("-") and entry[1:].isdigit():
        groups.setdefault(entry, {"requireMention": False})
    else:
        allow_from.append(entry)
dm_policy = "open" if "*" in allow_from else None
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
            "streaming": {"mode": "off"},
            "allowFrom": allow_from,
            **({"groups": groups} if groups else {}),
            **({"dmPolicy": dm_policy} if dm_policy else {}),
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
    echo "[entrypoint] Config created at $CONFIG_FILE"
else
    echo "[entrypoint] Config exists, skipping generation"
    echo "  NOTE: Changes to OPENCLAW_PROVIDER, OPENCLAW_MODEL, model credentials,"
    echo "  TELEGRAM_BOT_TOKEN, or TELEGRAM_ALLOW_FROM env vars will NOT take effect until the volume is reset."
    echo "  To reconfigure: docker compose down -v && docker compose up -d"

    python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

config_file = sys.argv[1]
with open(config_file) as f:
    config = json.load(f)

telegram = config.get("channels", {}).get("telegram")
if not isinstance(telegram, dict):
    raise SystemExit(0)

changed = False

# Migrate legacy streaming keys. OpenClaw deprecated the flat form
# (streamMode, scalar `streaming`, chunkMode, blockStreaming, draftChunk,
# blockStreamingCoalesce) in favour of nested `streaming.{mode,chunkMode,
# preview.chunk,block.enabled,block.coalesce}`. Strip the legacy keys and
# set `streaming.mode = "off"` to match our intent.
legacy_streaming_keys = ("streamMode", "chunkMode", "blockStreaming", "draftChunk", "blockStreamingCoalesce")
for key in legacy_streaming_keys:
    if key in telegram:
        del telegram[key]
        changed = True

streaming = telegram.get("streaming")
if not isinstance(streaming, dict):
    # Either missing or a legacy scalar (e.g. "off"/"on"/bool) — replace with a dict.
    telegram["streaming"] = {"mode": "off"}
    changed = True
elif streaming.get("mode") != "off":
    streaming["mode"] = "off"
    changed = True

normalized = []
groups = telegram.setdefault("groups", {})
for raw in telegram.get("allowFrom") or []:
    entry = str(raw).strip()
    lower = entry.lower()
    if lower.startswith(("tg:", "telegram:")):
        entry = entry.split(":", 1)[1].strip()
        changed = True
    if entry == "*":
        normalized.append(entry)
        if telegram.get("dmPolicy") != "open":
            telegram["dmPolicy"] = "open"
            changed = True
    elif entry.startswith("-") and entry[1:].isdigit():
        groups.setdefault(entry, {"requireMention": False})
        changed = True
    else:
        normalized.append(entry)

if normalized != (telegram.get("allowFrom") or []):
    telegram["allowFrom"] = normalized
    changed = True
if not groups and "groups" in telegram:
    del telegram["groups"]
if changed:
    with open(config_file, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
    print("[entrypoint] Migrated Telegram allowFrom entries in existing config")
PY
fi

# Agents are declared directly in openclaw.json above. Avoid calling
# `openclaw agents list/add` during container boot: on headless first boot it
# may wait for daemon state and block the entrypoint before the gateway starts.

# --- Per-agent exec approvals ---
# Agents run unattended in full exec mode. Workspace layout and prompts keep the
# concierge focused on routing while specialists own DB/Python analysis.
if [ ! -f "$APPROVALS_FILE" ]; then
    echo "[entrypoint] Creating per-agent exec-approvals.json..."
    cat > "$APPROVALS_FILE" << EOF
{
  "version": 1,
  "defaults": {
    "security": "full",
    "ask": "off",
    "askFallback": "off"
  },
  "agents": {
    "main": {
      "security": "full",
      "ask": "off",
      "askFallback": "off",
      "autoAllowSkills": true
    },
    "analyst": {
      "security": "full",
      "ask": "off",
      "askFallback": "off",
      "autoAllowSkills": true
    },
    "data-scientist": {
      "security": "full",
      "ask": "off",
      "askFallback": "off",
      "autoAllowSkills": true
    },
    "customer-intel": {
      "security": "full",
      "ask": "off",
      "askFallback": "off",
      "autoAllowSkills": true
    }
  }
}
EOF
    echo "[entrypoint] Approvals written"
else
    echo "[entrypoint] Exec approvals exist, skipping creation"
    python3 - "$APPROVALS_FILE" <<'PY'
import json
import sys

approvals_file = sys.argv[1]
with open(approvals_file) as f:
    approvals = json.load(f)

changed = False

# OpenClaw clamps hostSecurity = min(defaults.security, agent.security). If
# defaults.security is "allowlist", the specialists' per-agent "full" gets
# capped back to "allowlist" and they match zero rules (their allowlist was
# intentionally emptied), so every mysql/python3/helper call fails with
# "allowlist miss". Upgrade old volumes that were written before this fix.
defaults = approvals.setdefault("defaults", {})
if defaults.get("security") != "full":
    defaults["security"] = "full"
    changed = True
if defaults.get("ask") != "off":
    defaults["ask"] = "off"
    changed = True
if defaults.get("askFallback") != "off":
    defaults["askFallback"] = "off"
    changed = True

# All 4 agents now run in `full` security mode. The concierge was previously
# allowlist-only, but small models (e.g. gemini-3-flash) consistently prepended
# `cd <workspace> && …` to helper invocations. OpenClaw splits chains on `&&`
# and evaluates each segment; `cd` is a shell builtin with no resolved path,
# so the `cd` segment could never match an allowlist entry and the whole
# command denied. That bricked the concierge's bootstrap reads and the model
# would improvise (python3, mysql, echo, ls, …) — all denied — producing
# the "fails a lot" UX. The container + TELEGRAM_ALLOW_FROM are the real
# perimeter; the SOUL/ROUTING prompts still tell the concierge to route
# instead of analyze.
for name in ("main", "analyst", "data-scientist", "customer-intel"):
    agent = approvals.setdefault("agents", {}).setdefault(name, {})
    target = {"security": "full", "ask": "off", "askFallback": "off", "autoAllowSkills": True}
    for key, value in target.items():
        if agent.get(key) != value:
            agent[key] = value
            changed = True
    if "allowlist" in agent:
        del agent["allowlist"]
        changed = True

if changed:
    with open(approvals_file, "w") as f:
        json.dump(approvals, f, indent=2)
        f.write("\n")
    print("[entrypoint] Reconciled exec approvals (full security mode, pruned stale allowlists)")
PY
fi

# --- Concierge workspace (the 'main' agent) ---
# No DB, no DATA_ANALYST.md, no skills — just routing + persona + memory rules.
echo "[entrypoint] Installing concierge workspace..."
seed_memory_files "$CONCIERGE_WS"
cp "$CONFIG_SRC/shared/BRAND.md"                       "$CONCIERGE_WS/BRAND.md"
cp "$CONFIG_SRC/shared/IDENTITY.md"                    "$CONCIERGE_WS/IDENTITY.md"
cp "$CONFIG_SRC/shared/USER.md"                        "$CONCIERGE_WS/USER.md"
cp "$CONFIG_SRC/shared/TOOLS.md"                       "$CONCIERGE_WS/TOOLS.md"
cp "$CONFIG_SRC/shared/HEARTBEAT.md"                   "$CONCIERGE_WS/HEARTBEAT.md"
cp "$CONFIG_SRC/shared/BOOTSTRAP.md"                   "$CONCIERGE_WS/BOOTSTRAP.md"
cp "$CONFIG_SRC/shared/MEMORY_RULES.md"                "$CONCIERGE_WS/MEMORY_RULES.md"
cp "$CONFIG_SRC/shared/read-workspace-file.sh"         "$CONCIERGE_WS/read-workspace-file.sh"
cp "$CONFIG_SRC/agents/concierge/SOUL.md"              "$CONCIERGE_WS/SOUL.md"
cp "$CONFIG_SRC/agents/concierge/AGENTS.md"            "$CONCIERGE_WS/AGENTS.md"
render_routing_md "$CONCIERGE_WS/ROUTING.md"           "$CONCIERGE_WS/invoke-specialist.sh"
cp "$CONFIG_SRC/agents/concierge/GROUP_CHAT.md"        "$CONCIERGE_WS/GROUP_CHAT.md"
cp "$CONFIG_SRC/agents/concierge/HEARTBEAT_GUIDE.md"   "$CONCIERGE_WS/HEARTBEAT_GUIDE.md"
cp "$CONFIG_SRC/shared/invoke-specialist.sh"           "$CONCIERGE_WS/invoke-specialist.sh"
chmod +x "$CONCIERGE_WS/read-workspace-file.sh"
chmod +x "$CONCIERGE_WS/invoke-specialist.sh"

# --- Specialist workspace installer ---
install_specialist() {
    local agent_dir="$1"
    local workspace="$2"
    local extra_file="$3"  # optional, e.g. TECHNICAL_SKILLS.md

    mkdir -p "$workspace/data"
    seed_memory_files "$workspace"

    # Shared files (BRAND, DATA_ANALYST, MEMORY_RULES, SCHEMA, chart helpers)
    cp "$CONFIG_SRC/shared/BRAND.md"            "$workspace/BRAND.md"
    cp "$CONFIG_SRC/shared/IDENTITY.md"         "$workspace/IDENTITY.md"
    cp "$CONFIG_SRC/shared/USER.md"             "$workspace/USER.md"
    cp "$CONFIG_SRC/shared/TOOLS.md"            "$workspace/TOOLS.md"
    cp "$CONFIG_SRC/shared/HEARTBEAT.md"        "$workspace/HEARTBEAT.md"
    cp "$CONFIG_SRC/shared/BOOTSTRAP.md"        "$workspace/BOOTSTRAP.md"
    cp "$CONFIG_SRC/shared/DATA_ANALYST.md"     "$workspace/DATA_ANALYST.md"
    cp "$CONFIG_SRC/shared/MEMORY_RULES.md"     "$workspace/MEMORY_RULES.md"
    cp "$CONFIG_SRC/shared/read-workspace-file.sh" "$workspace/read-workspace-file.sh"
    cp "$CONFIG_SRC/shared/run-workspace-python.sh" "$workspace/run-workspace-python.sh"
    cp "$CONFIG_SRC/shared/query-db.sh" "$workspace/query-db.sh"
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

    # MySQL read-only connection config + python3 into the workspace
    write_mysql_readonly_config "$workspace"
    ln -sf "$PYTHON3_PATH"  "$workspace/data/python3"
    chmod +x "$workspace/read-workspace-file.sh"
    chmod +x "$workspace/run-workspace-python.sh"
    chmod +x "$workspace/query-db.sh"
}

echo "[entrypoint] Installing specialist workspaces..."
install_specialist "analyst"        "$ANALYST_WS"   ""
install_specialist "data-scientist" "$DS_WS"        "TECHNICAL_SKILLS.md"
install_specialist "customer-intel" "$CUSTOMER_WS"  ""

echo "[entrypoint] Setup complete. Starting gateway..."
unset MYSQL_ROOT_PASSWORD
exec node dist/index.js gateway run
