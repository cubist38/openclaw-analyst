#!/bin/bash
# Install Brewlytics (multi-agent OpenClaw analyst) on the host
# Usage: bash install.sh
#
# For most users, Docker (docker compose up -d) is the recommended path.
# This script is for local installs where you want to run the agents on
# your own host, outside a container.
#
# What it does:
#   1. Checks dependencies (Node, Python 3, sqlite3, OpenClaw)
#   2. Creates a Python venv with pandas/matplotlib/seaborn/scipy
#   3. Provisions 4 agent workspaces (concierge + 3 specialists)
#   4. Generates the shared SQLite DB once; symlinks it into each specialist
#   5. Writes a per-agent exec-approvals.json (concierge: wrapper only;
#      specialists: sqlite3 + python3)
#
# Prerequisites: run `openclaw configure` first so the default 'main' agent
# exists and Telegram is bound.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_DIR="${HOME}/.openclaw"
SHARED_DATA_DIR="${OPENCLAW_DIR}/shared-data"
SHARED_DB="${SHARED_DATA_DIR}/starbucks_business.db"

CONCIERGE_WS="${OPENCLAW_WORKSPACE:-${OPENCLAW_DIR}/workspace}"  # default 'main'
ANALYST_WS="${OPENCLAW_DIR}/workspace-analyst"
DS_WS="${OPENCLAW_DIR}/workspace-ds"
CUSTOMER_WS="${OPENCLAW_DIR}/workspace-customer"

CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
APPROVALS_FILE="${OPENCLAW_DIR}/exec-approvals.json"
CONFIG_SRC="${SCRIPT_DIR}/openclaw-config"

MODEL="${OPENCLAW_MODEL:-openrouter/x-ai/grok-3-fast}"

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

command -v sqlite3 &>/dev/null || { echo "  ERROR: sqlite3 required"; exit 1; }
echo "  sqlite3: $(sqlite3 --version | head -1)"

echo ""

# --- [2/7] Python venv ---
echo "[2/7] Installing Python packages..."

VENV_DIR="$SCRIPT_DIR/.venv"
if [ ! -f "$VENV_DIR/bin/pip" ]; then
    echo "  Creating venv at $VENV_DIR..."
    rm -rf "$VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt" \
    && echo "  Installed: pyyaml, pandas, matplotlib, seaborn, scipy" \
    || { echo "  ERROR: pip install failed"; exit 1; }

PYTHON3="$VENV_DIR/bin/python3"
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

for entry in "analyst:${ANALYST_WS}" "data-scientist:${DS_WS}" "customer-intel:${CUSTOMER_WS}"; do
    name="${entry%%:*}"
    ws="${entry##*:}"
    if openclaw agents list 2>/dev/null | grep -q " $name "; then
        echo "  Agent '$name' already exists"
    else
        openclaw agents add "$name" --workspace "$ws" --model "$MODEL" \
            && echo "  Added agent '$name' at $ws" \
            || echo "  WARNING: 'openclaw agents add $name' failed — check: openclaw agents list"
    fi
done
echo ""

# --- [5/7] Generate shared DB ---
echo "[5/7] Generating shared database..."
mkdir -p "$SHARED_DATA_DIR"

if [ -f "$SHARED_DB" ]; then
    echo "  DB exists at $SHARED_DB (skipping; rm to regenerate)"
else
    mkdir -p "$CONCIERGE_WS/data"
    "$PYTHON3" "$SCRIPT_DIR/generate_starbucks_db.py"
    mv "$CONCIERGE_WS/data/starbucks_business.db" "$SHARED_DB"
    rmdir "$CONCIERGE_WS/data" 2>/dev/null || true
    echo "  DB generated at $SHARED_DB"
fi
echo ""

# --- [6/7] Install workspace files ---
echo "[6/7] Installing workspace files..."

# Concierge (main) — no DB, no analyst playbook, no skills
mkdir -p "$CONCIERGE_WS/memory"
cp "$CONFIG_SRC/shared/BRAND.md"                     "$CONCIERGE_WS/BRAND.md"
cp "$CONFIG_SRC/shared/MEMORY_RULES.md"              "$CONCIERGE_WS/MEMORY_RULES.md"
cp "$CONFIG_SRC/agents/concierge/SOUL.md"            "$CONCIERGE_WS/SOUL.md"
cp "$CONFIG_SRC/agents/concierge/AGENTS.md"          "$CONCIERGE_WS/AGENTS.md"
cp "$CONFIG_SRC/agents/concierge/ROUTING.md"         "$CONCIERGE_WS/ROUTING.md"
cp "$CONFIG_SRC/agents/concierge/GROUP_CHAT.md"      "$CONCIERGE_WS/GROUP_CHAT.md"
cp "$CONFIG_SRC/agents/concierge/HEARTBEAT_GUIDE.md" "$CONCIERGE_WS/HEARTBEAT_GUIDE.md"
cp "$CONFIG_SRC/shared/invoke-specialist.sh"         "$CONCIERGE_WS/invoke-specialist.sh"
chmod +x "$CONCIERGE_WS/invoke-specialist.sh"
echo "  Installed concierge in $CONCIERGE_WS"

install_specialist() {
    local agent_dir="$1"
    local workspace="$2"
    local extra_file="$3"

    mkdir -p "$workspace/data" "$workspace/memory"

    cp "$CONFIG_SRC/shared/BRAND.md"            "$workspace/BRAND.md"
    cp "$CONFIG_SRC/shared/DATA_ANALYST.md"     "$workspace/DATA_ANALYST.md"
    cp "$CONFIG_SRC/shared/MEMORY_RULES.md"     "$workspace/MEMORY_RULES.md"
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

    ln -sf "$SHARED_DB" "$workspace/data/starbucks_business.db"
    ln -sf "$PYTHON3"   "$workspace/data/python3"
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

SQLITE3_PATH="$(which sqlite3)"
SYS_PYTHON="$(which python3)"

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
        { "pattern": "${PYTHON3}" },
        { "pattern": "${SYS_PYTHON}" },
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
        { "pattern": "${PYTHON3}" },
        { "pattern": "${SYS_PYTHON}" },
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
        { "pattern": "${PYTHON3}" },
        { "pattern": "${SYS_PYTHON}" },
        { "pattern": "${CUSTOMER_WS}/data/python3" }
      ]
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
