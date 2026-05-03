#!/bin/bash
# Install Brewlytics (multi-agent OpenClaw analyst) on the host
# Usage: bash install.sh
#
# For most users, Docker (docker compose up -d) is the recommended path.
# This script is for local installs where you want to run the agents on
# your own host, outside a container.
#
# What it does:
#   1. Checks dependencies (Node, Python 3, MySQL client, OpenClaw)
#   2. Creates a uv-managed Python venv with pandas/matplotlib/seaborn/scipy
#   3. Provisions 4 agent workspaces (concierge + 3 specialists)
#   4. Applies generated MySQL init SQL and configures a read-only query user
#   5. Writes exec-approvals.json for unattended local analysis
#
# Prerequisites: run `openclaw configure` first so the default 'main' agent
# exists and Telegram is bound.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_DIR="${HOME}/.openclaw"
CONCIERGE_WS="${OPENCLAW_WORKSPACE:-${OPENCLAW_DIR}/workspace}"  # default 'main'
ANALYST_WS="${OPENCLAW_DIR}/workspace-analyst"
DS_WS="${OPENCLAW_DIR}/workspace-ds"
CUSTOMER_WS="${OPENCLAW_DIR}/workspace-customer"

CONCIERGE_AGENT_DIR="${OPENCLAW_DIR}/agents/main/agent"
ANALYST_AGENT_DIR="${OPENCLAW_DIR}/agents/analyst/agent"
DS_AGENT_DIR="${OPENCLAW_DIR}/agents/data-scientist/agent"
CUSTOMER_AGENT_DIR="${OPENCLAW_DIR}/agents/customer-intel/agent"

CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
APPROVALS_FILE="${OPENCLAW_DIR}/exec-approvals.json"
CONFIG_SRC="${SCRIPT_DIR}/openclaw-config"

MODEL="${OPENCLAW_MODEL:-openrouter/x-ai/grok-3-fast}"
CONCIERGE_MODEL="${OPENCLAW_CONCIERGE_MODEL:-$MODEL}"
ANALYST_MODEL="${OPENCLAW_ANALYST_MODEL:-$MODEL}"
DS_MODEL="${OPENCLAW_DS_MODEL:-$MODEL}"
CUSTOMER_MODEL="${OPENCLAW_CUSTOMER_MODEL:-$MODEL}"

MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_DATABASE="${MYSQL_DATABASE:-brewlytics}"
MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
MYSQL_READONLY_USER="${MYSQL_READONLY_USER:-brewlytics_ro}"
MYSQL_READONLY_PASSWORD="${MYSQL_READONLY_PASSWORD:-brewlytics_readonly_change_me}"

mysql_admin() {
    MYSQL_PWD="${MYSQL_ROOT_PASSWORD:-}" mysql \
        --host="$MYSQL_HOST" \
        --port="$MYSQL_PORT" \
        --user="$MYSQL_ROOT_USER" \
        --protocol=TCP \
        "$@"
}

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

reconcile_openclaw_agents_config() {
    python3 - "$CONFIG_FILE" "$MODEL" "$CONCIERGE_MODEL" "$ANALYST_MODEL" "$DS_MODEL" "$CUSTOMER_MODEL" "$CONCIERGE_WS" "$ANALYST_WS" "$DS_WS" "$CUSTOMER_WS" "$CONCIERGE_AGENT_DIR" "$ANALYST_AGENT_DIR" "$DS_AGENT_DIR" "$CUSTOMER_AGENT_DIR" <<'PY'
import json
import os
import sys

(
    config_file,
    default_model,
    concierge_model,
    analyst_model,
    ds_model,
    customer_model,
    concierge_ws,
    analyst_ws,
    ds_ws,
    customer_ws,
    concierge_agent_dir,
    analyst_agent_dir,
    ds_agent_dir,
    customer_agent_dir,
) = sys.argv[1:]

with open(config_file) as f:
    config = json.load(f)

changed = False

def set_if_changed(target, key, value):
    global changed
    if target.get(key) != value:
        target[key] = value
        changed = True

all_models = [default_model, concierge_model, analyst_model, ds_model, customer_model]
uses_openrouter = any(m.startswith("openrouter/") for m in all_models)
uses_vllm = any(m.startswith("vllm/") for m in all_models)

env = config.setdefault("env", {})
if uses_openrouter and os.environ.get("OPENROUTER_API_KEY"):
    set_if_changed(env, "OPENROUTER_API_KEY", os.environ["OPENROUTER_API_KEY"])
if uses_vllm:
    set_if_changed(env, "VLLM_API_KEY", os.environ.get("VLLM_API_KEY", "vllm-local"))

agents_config = config.setdefault("agents", {})
agent_defaults = agents_config.setdefault("defaults", {})
set_if_changed(agent_defaults, "model", default_model)
set_if_changed(agent_defaults, "workspace", concierge_ws)
set_if_changed(agent_defaults, "skills", [])

desired_agents = [
    {
        "id": "main",
        "default": True,
        "name": "concierge",
        "workspace": concierge_ws,
        "agentDir": concierge_agent_dir,
        "model": concierge_model,
        "skills": [],
    },
    {
        "id": "analyst",
        "name": "analyst",
        "workspace": analyst_ws,
        "agentDir": analyst_agent_dir,
        "model": analyst_model,
        "skills": [
            "compare",
            "executive-summary",
            "labor-analysis",
            "marketing-roi",
            "product-mix",
            "store-health",
        ],
    },
    {
        "id": "data-scientist",
        "name": "data-scientist",
        "workspace": ds_ws,
        "agentDir": ds_agent_dir,
        "model": ds_model,
        "skills": ["anomaly-scan", "trend"],
    },
    {
        "id": "customer-intel",
        "name": "customer-intel",
        "workspace": customer_ws,
        "agentDir": customer_agent_dir,
        "model": customer_model,
        "skills": ["customer-insights"],
    },
]

agent_list = agents_config.setdefault("list", [])
if not isinstance(agent_list, list):
    agent_list = []
    agents_config["list"] = agent_list
    changed = True

for desired in desired_agents:
    existing = next((a for a in agent_list if isinstance(a, dict) and a.get("id") == desired["id"]), None)
    if existing is None:
        agent_list.append(desired)
        changed = True
        continue
    for key, value in desired.items():
        set_if_changed(existing, key, value)

bindings = config.setdefault("bindings", [])
if not isinstance(bindings, list):
    bindings = []
    config["bindings"] = bindings
    changed = True
if not any(
    isinstance(binding, dict)
    and binding.get("agentId") == "main"
    and isinstance(binding.get("match"), dict)
    and binding["match"].get("channel") == "telegram"
    for binding in bindings
):
    bindings.insert(0, {"agentId": "main", "match": {"channel": "telegram"}})
    changed = True

if uses_vllm:
    seen = set()
    distinct_vllm_ids = []
    for model in all_models:
        if not model.startswith("vllm/"):
            continue
        model_id = model.removeprefix("vllm/")
        if model_id not in seen:
            seen.add(model_id)
            distinct_vllm_ids.append(model_id)

    primary_vllm_id = default_model.removeprefix("vllm/") if default_model.startswith("vllm/") else None
    vllm_context_window = int(os.environ.get("VLLM_CONTEXT_WINDOW", "128000"))
    vllm_max_tokens = int(os.environ.get("VLLM_MAX_TOKENS", "8192"))
    vllm_reasoning = os.environ.get("VLLM_REASONING", "false").lower() == "true"

    models_config = config.setdefault("models", {})
    set_if_changed(models_config, "mode", "merge")
    providers = models_config.setdefault("providers", {})
    vllm_provider = providers.setdefault("vllm", {})
    for key, value in {
        "baseUrl": os.environ.get("VLLM_BASE_URL", "http://127.0.0.1:8000/v1"),
        "apiKey": "${VLLM_API_KEY}",
        "api": "openai-completions",
    }.items():
        set_if_changed(vllm_provider, key, value)

    vllm_models = vllm_provider.get("models")
    if not isinstance(vllm_models, list):
        vllm_models = []
        vllm_provider["models"] = vllm_models
        changed = True

    for model_id in distinct_vllm_ids:
        target = next(
            (item for item in vllm_models if isinstance(item, dict) and item.get("id") == model_id),
            None,
        )
        if target is None:
            target = {"id": model_id}
            vllm_models.append(target)
            changed = True
        desired = {
            "name": (
                os.environ.get("VLLM_MODEL_NAME", model_id)
                if model_id == primary_vllm_id
                else model_id
            ),
            "reasoning": vllm_reasoning,
            "input": ["text"],
            "cost": {
                "input": 0,
                "output": 0,
                "cacheRead": 0,
                "cacheWrite": 0,
            },
            "contextWindow": vllm_context_window,
            "contextTokens": vllm_context_window,
            "maxTokens": vllm_max_tokens,
        }
        for key, value in desired.items():
            set_if_changed(target, key, value)

if changed:
    with open(config_file, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
PY
}

echo "=== Brewlytics Multi-Agent Setup ==="
echo ""

# --- [1/7] Dependencies ---
echo "[1/7] Checking dependencies..."

if ! command -v node &>/dev/null; then
    echo "  ERROR: Node.js 22+ required. Install from https://nodejs.org/"
    exit 1
fi
echo "  Node.js: $(node -v)"

if ! command -v openclaw &>/dev/null; then
    echo "  OpenClaw not found. Installing via npm..."
    npm install -g openclaw@latest
fi
echo "  OpenClaw: $(openclaw --version 2>&1 | head -1)"

command -v python3 &>/dev/null || { echo "  ERROR: python3 required"; exit 1; }
echo "  Python: $(python3 --version)"

command -v uv &>/dev/null || { echo "  ERROR: uv required. Install from https://docs.astral.sh/uv/"; exit 1; }
echo "  uv: $(uv --version)"

command -v mysql &>/dev/null || { echo "  ERROR: mysql client required"; exit 1; }
echo "  mysql: $(mysql --version | head -1)"

echo ""

# --- [2/7] Python venv ---
echo "[2/7] Installing Python packages..."

VENV_DIR="$SCRIPT_DIR/.venv"
if [ ! -f "$VENV_DIR/bin/python" ]; then
    echo "  Creating venv at $VENV_DIR..."
    rm -rf "$VENV_DIR"
    uv venv "$VENV_DIR"
fi

uv pip install --python "$VENV_DIR/bin/python" --quiet -r "$SCRIPT_DIR/requirements.txt" \
    && echo "  Installed: pyyaml, pymysql, pandas, matplotlib, seaborn, scipy" \
    || { echo "  ERROR: uv pip install failed"; exit 1; }

PYTHON3="$VENV_DIR/bin/python"
echo "  Using Python: $PYTHON3"
echo ""

# --- [3/7] Check openclaw configure ran ---
echo "[3/7] Checking OpenClaw configuration..."

if [ ! -f "$CONFIG_FILE" ]; then
    echo ""
    echo "  ERROR: OpenClaw is not configured yet. Run:"
    echo "    openclaw configure"
    echo "  Then re-run this script."
    exit 1
fi

if [ ! -d "$CONCIERGE_WS" ]; then
    echo "  ERROR: Concierge workspace not found at $CONCIERGE_WS"
    echo "  Run 'openclaw configure' first."
    exit 1
fi
echo "  Concierge workspace: $CONCIERGE_WS"
echo ""

# --- [4/7] Provision specialist agents ---
echo "[4/7] Provisioning specialist agents..."

ensure_agent() {
    local name="$1"
    local ws="$2"
    local agent_dir="$3"
    local agent_model="$4"

    if openclaw agents list 2>/dev/null | grep -q " $name "; then
        echo "  Agent '$name' already exists"
    else
        openclaw agents add "$name" --workspace "$ws" --agent-dir "$agent_dir" --model "$agent_model" \
            && echo "  Added agent '$name' at $ws" \
            || echo "  WARNING: 'openclaw agents add $name' failed — check: openclaw agents list"
    fi
}

ensure_agent "analyst"        "$ANALYST_WS" "$ANALYST_AGENT_DIR" "$ANALYST_MODEL"
ensure_agent "data-scientist" "$DS_WS"      "$DS_AGENT_DIR"      "$DS_MODEL"
ensure_agent "customer-intel" "$CUSTOMER_WS" "$CUSTOMER_AGENT_DIR" "$CUSTOMER_MODEL"

reconcile_openclaw_agents_config
echo "  Reconciled OpenClaw agent config, per-agent models, skill visibility, and Telegram binding"
echo ""

# --- [5/7] Apply generated MySQL init SQL ---
echo "[5/7] Applying generated MySQL database files..."

if ! mysql_admin --execute="SELECT 1" >/dev/null 2>&1; then
    echo "  ERROR: Cannot connect to MySQL at ${MYSQL_HOST}:${MYSQL_PORT} as ${MYSQL_ROOT_USER}."
    echo "  Set MYSQL_ROOT_PASSWORD if the root account requires a password."
    exit 1
fi

mysql_admin --execute="CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
TABLE_COUNT="$(mysql_admin --batch --skip-column-names "$MYSQL_DATABASE" --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE';")"
if [ "${TABLE_COUNT:-0}" = "0" ]; then
    if [ ! -f "$SCRIPT_DIR/database/init/01_schema.sql" ] || [ ! -f "$SCRIPT_DIR/database/init/02_seed.sql" ]; then
        echo "  Generated SQL files missing; regenerating with uv-managed Python..."
        "$PYTHON3" "$SCRIPT_DIR/generate_starbucks_db.py"
    fi
    mysql_admin "$MYSQL_DATABASE" < "$SCRIPT_DIR/database/init/01_schema.sql"
    mysql_admin "$MYSQL_DATABASE" < "$SCRIPT_DIR/database/init/02_seed.sql"
else
    echo "  MySQL database already has ${TABLE_COUNT} tables (skipping seed import)"
fi

mysql_admin "$MYSQL_DATABASE" <<SQL
CREATE USER IF NOT EXISTS '${MYSQL_READONLY_USER}'@'%' IDENTIFIED BY '${MYSQL_READONLY_PASSWORD}';
ALTER USER '${MYSQL_READONLY_USER}'@'%' IDENTIFIED BY '${MYSQL_READONLY_PASSWORD}';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${MYSQL_READONLY_USER}'@'%';
GRANT SELECT ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_READONLY_USER}'@'%';
FLUSH PRIVILEGES;
SQL
echo "  Read-only user '${MYSQL_READONLY_USER}' has SELECT on ${MYSQL_DATABASE}.*"
echo ""

# --- [6/7] Install workspace files ---
echo "[6/7] Installing workspace files..."

# Concierge (main) — no DB, no analyst playbook, no skills
seed_memory_files "$CONCIERGE_WS"
cp "$CONFIG_SRC/shared/BRAND.md"                     "$CONCIERGE_WS/BRAND.md"
cp "$CONFIG_SRC/shared/IDENTITY.md"                  "$CONCIERGE_WS/IDENTITY.md"
cp "$CONFIG_SRC/shared/USER.md"                      "$CONCIERGE_WS/USER.md"
cp "$CONFIG_SRC/shared/TOOLS.md"                     "$CONCIERGE_WS/TOOLS.md"
cp "$CONFIG_SRC/shared/HEARTBEAT.md"                 "$CONCIERGE_WS/HEARTBEAT.md"
cp "$CONFIG_SRC/shared/BOOTSTRAP.md"                 "$CONCIERGE_WS/BOOTSTRAP.md"
cp "$CONFIG_SRC/shared/MEMORY_RULES.md"              "$CONCIERGE_WS/MEMORY_RULES.md"
cp "$CONFIG_SRC/shared/read-workspace-file.sh"       "$CONCIERGE_WS/read-workspace-file.sh"
cp "$CONFIG_SRC/agents/concierge/SOUL.md"            "$CONCIERGE_WS/SOUL.md"
cp "$CONFIG_SRC/agents/concierge/AGENTS.md"          "$CONCIERGE_WS/AGENTS.md"
cp "$CONFIG_SRC/shared/invoke-specialist.sh"         "$CONCIERGE_WS/invoke-specialist.sh"
render_routing_md "$CONCIERGE_WS/ROUTING.md"         "$CONCIERGE_WS/invoke-specialist.sh"
cp "$CONFIG_SRC/agents/concierge/GROUP_CHAT.md"      "$CONCIERGE_WS/GROUP_CHAT.md"
cp "$CONFIG_SRC/agents/concierge/HEARTBEAT_GUIDE.md" "$CONCIERGE_WS/HEARTBEAT_GUIDE.md"
chmod +x "$CONCIERGE_WS/read-workspace-file.sh"
chmod +x "$CONCIERGE_WS/invoke-specialist.sh"
echo "  Installed concierge in $CONCIERGE_WS"

install_specialist() {
    local agent_dir="$1"
    local workspace="$2"
    local extra_file="$3"

    mkdir -p "$workspace/data"
    seed_memory_files "$workspace"

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
    cp "$CONFIG_SRC/shared/query-db.sh"         "$workspace/query-db.sh"
    cp "$CONFIG_SRC/shared/data/SCHEMA.md"      "$workspace/data/SCHEMA.md"
    cp "$CONFIG_SRC/shared/data/brew_chart.py"  "$workspace/data/brew_chart.py"
    cp "$CONFIG_SRC/shared/data/send_photo.py"  "$workspace/data/send_photo.py"

    cp "$CONFIG_SRC/agents/$agent_dir/SOUL.md"   "$workspace/SOUL.md"
    cp "$CONFIG_SRC/agents/$agent_dir/AGENTS.md" "$workspace/AGENTS.md"

    if [ -n "$extra_file" ]; then
        cp "$CONFIG_SRC/agents/$agent_dir/$extra_file" "$workspace/$extra_file"
    fi

    rm -rf "$workspace/skills"
    cp -r "$CONFIG_SRC/agents/$agent_dir/skills" "$workspace/skills"

    write_mysql_readonly_config "$workspace"
    ln -sf "$PYTHON3"   "$workspace/data/python3"
    chmod +x "$workspace/read-workspace-file.sh"
    chmod +x "$workspace/run-workspace-python.sh"
    chmod +x "$workspace/query-db.sh"
}

install_specialist "analyst"        "$ANALYST_WS"   ""
echo "  Installed analyst in $ANALYST_WS"
install_specialist "data-scientist" "$DS_WS"        "TECHNICAL_SKILLS.md"
echo "  Installed data-scientist in $DS_WS"
install_specialist "customer-intel" "$CUSTOMER_WS"  ""
echo "  Installed customer-intel in $CUSTOMER_WS"
echo ""

# --- [7/7] Per-agent exec approvals ---
echo "[7/7] Writing per-agent exec-approvals.json..."

# Back up existing approvals if present (security config — don't silently overwrite)
if [ -f "$APPROVALS_FILE" ]; then
    BACKUP="${APPROVALS_FILE}.bak.$(date +%s)"
    cp "$APPROVALS_FILE" "$BACKUP"
    echo "  Backed up existing approvals to $BACKUP"
fi

cat > "$APPROVALS_FILE" << EOF
{
  "version": 1,
  "defaults": {
    "security": "full",
    "ask": "off",
    "askFallback": "full"
  },
  "agents": {
    "main": {
      "security": "allowlist",
      "ask": "off",
      "askFallback": "allowlist",
      "autoAllowSkills": false,
      "allowlist": [
        { "pattern": "${CONCIERGE_WS}/read-workspace-file.sh" },
        { "pattern": "${CONCIERGE_WS}/invoke-specialist.sh" }
      ]
    },
    "analyst": {
      "security": "full",
      "ask": "off",
      "askFallback": "full",
      "autoAllowSkills": true
    },
    "data-scientist": {
      "security": "full",
      "ask": "off",
      "askFallback": "full",
      "autoAllowSkills": true
    },
    "customer-intel": {
      "security": "full",
      "ask": "off",
      "askFallback": "full",
      "autoAllowSkills": true
    }
  }
}
EOF

echo "  Approvals written to $APPROVALS_FILE"
echo ""

echo "=== Setup complete! ==="
echo ""
echo "Start the bot:"
echo "  openclaw gateway run"
echo ""
echo "Message your Telegram bot — the concierge will route to specialists."
