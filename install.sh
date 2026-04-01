#!/bin/bash
# Install OpenClaw analyst bot configuration
# Usage: bash install.sh
#
# This script:
# 1. Checks dependencies (Node.js, Python 3, sqlite3, OpenClaw)
# 2. Installs Python packages (pandas, matplotlib, seaborn)
# 3. Copies analyst config files into the OpenClaw workspace
# 4. Generates the Starbucks SQLite database
# 5. Adds sqlite3 and python3 to the exec allowlist
#
# Prerequisites: run `openclaw configure` first to set up API key and Telegram

set -e

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== OpenClaw Business Analyst Bot Setup ==="
echo ""

# --- Step 1: Check dependencies ---
echo "[1/6] Checking dependencies..."

if ! command -v node &>/dev/null; then
    echo "  ERROR: Node.js is required but not installed."
    echo "  Install it from https://nodejs.org/ or via your package manager:"
    echo "    macOS:  brew install node@24"
    echo "    Linux:  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo bash - && sudo apt-get install -y nodejs"
    exit 1
else
    echo "  Node.js: $(node -v)"
fi

if ! command -v openclaw &>/dev/null; then
    echo "  OpenClaw not found. Installing..."
    npm install -g openclaw@latest
else
    echo "  OpenClaw: $(openclaw --version 2>&1 | head -1)"
fi

if ! command -v python3 &>/dev/null; then
    echo "  ERROR: Python 3 is required but not installed."
    exit 1
else
    echo "  Python: $(python3 --version)"
fi

if ! command -v sqlite3 &>/dev/null; then
    echo "  ERROR: sqlite3 is required but not installed."
    exit 1
else
    echo "  sqlite3: $(sqlite3 --version | head -1)"
fi

echo ""

# --- Step 2: Set up Python virtual environment and install packages ---
echo "[2/6] Installing Python packages..."

VENV_DIR="$SCRIPT_DIR/.venv"

if [ ! -f "$VENV_DIR/bin/pip" ]; then
    echo "  Creating virtual environment at $VENV_DIR..."
    rm -rf "$VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt" && \
    echo "  Installed: pyyaml, pandas, matplotlib, seaborn" || \
    { echo "  ERROR: Failed to install Python packages."; exit 1; }

# Use the venv python for all subsequent steps and for the bot's exec allowlist
PYTHON3="$VENV_DIR/bin/python3"
echo "  Using Python: $PYTHON3"

echo ""

# --- Step 3: Check OpenClaw is configured ---
echo "[3/6] Checking OpenClaw configuration..."

if [ ! -f "$HOME/.openclaw/openclaw.json" ]; then
    echo ""
    echo "  OpenClaw is not configured yet. Run:"
    echo ""
    echo "    openclaw configure"
    echo ""
    echo "  Then re-run this script."
    exit 1
fi

if [ ! -d "$WORKSPACE" ]; then
    echo "  ERROR: Workspace not found at $WORKSPACE"
    echo "  Run 'openclaw configure' first."
    exit 1
fi

echo "  Workspace: $WORKSPACE"
echo ""

# --- Step 4: Copy config files ---
echo "[4/6] Installing analyst configuration files..."

mkdir -p "$WORKSPACE/data"

cp "$SCRIPT_DIR/openclaw-config/SOUL.md" "$WORKSPACE/SOUL.md"
echo "  Copied SOUL.md (analyst identity)"

cp "$SCRIPT_DIR/openclaw-config/DATA_ANALYST.md" "$WORKSPACE/DATA_ANALYST.md"
echo "  Copied DATA_ANALYST.md (analyst playbook)"

cp "$SCRIPT_DIR/openclaw-config/TECHNICAL_SKILLS.md" "$WORKSPACE/TECHNICAL_SKILLS.md"
echo "  Copied TECHNICAL_SKILLS.md (advanced technical skills)"

cp "$SCRIPT_DIR/openclaw-config/AGENTS.md" "$WORKSPACE/AGENTS.md"
echo "  Copied AGENTS.md (startup routine)"

cp "$SCRIPT_DIR/openclaw-config/MEMORY_RULES.md" "$WORKSPACE/MEMORY_RULES.md"
echo "  Copied MEMORY_RULES.md (memory system)"

cp "$SCRIPT_DIR/openclaw-config/GROUP_CHAT.md" "$WORKSPACE/GROUP_CHAT.md"
echo "  Copied GROUP_CHAT.md (group chat rules)"

cp "$SCRIPT_DIR/openclaw-config/HEARTBEAT_GUIDE.md" "$WORKSPACE/HEARTBEAT_GUIDE.md"
echo "  Copied HEARTBEAT_GUIDE.md (heartbeat system)"

cp -r "$SCRIPT_DIR/openclaw-config/skills" "$WORKSPACE/skills"
echo "  Copied skills/ (9 analyst skills)"

cp "$SCRIPT_DIR/openclaw-config/data/SCHEMA.md" "$WORKSPACE/data/SCHEMA.md"
echo "  Copied data/SCHEMA.md (database schema)"

echo ""

# --- Step 5: Generate database (skip if already exists) ---
echo "[5/6] Generating Starbucks business database..."

DB_FILE="$WORKSPACE/data/starbucks_business.db"
if [ -f "$DB_FILE" ]; then
    echo "  Database already exists at $DB_FILE"
    echo "  To regenerate, delete it first: rm \"$DB_FILE\""
else
    "$PYTHON3" "$SCRIPT_DIR/generate_starbucks_db.py"
fi
echo ""

# --- Step 6: Allowlist sqlite3 and python3 ---
echo "[6/6] Adding sqlite3 and python3 to exec allowlist..."

SQLITE3_PATH="$(which sqlite3)"
openclaw approvals allowlist add "$SQLITE3_PATH" 2>/dev/null && \
    echo "  Allowlisted: $SQLITE3_PATH" || \
    echo "  Already allowlisted or failed — check with: openclaw approvals get"

# Allowlist both the venv python3 (has charting libs) and system python3 (fallback)
openclaw approvals allowlist add "$PYTHON3" 2>/dev/null && \
    echo "  Allowlisted: $PYTHON3 (venv — has pandas, matplotlib, seaborn)" || \
    echo "  Already allowlisted or failed — check with: openclaw approvals get"

SYSTEM_PYTHON3="$(which python3)"
if [ "$SYSTEM_PYTHON3" != "$PYTHON3" ]; then
    openclaw approvals allowlist add "$SYSTEM_PYTHON3" 2>/dev/null && \
        echo "  Allowlisted: $SYSTEM_PYTHON3 (system)" || \
        echo "  Already allowlisted or failed"
fi

# Symlink venv python3 into workspace so the bot can always use data/python3
ln -sf "$PYTHON3" "$WORKSPACE/data/python3"
echo "  Linked: $WORKSPACE/data/python3 -> $PYTHON3"

# Allowlist the symlink path too (this is what the bot will actually call)
openclaw approvals allowlist add "$WORKSPACE/data/python3" 2>/dev/null && \
    echo "  Allowlisted: $WORKSPACE/data/python3" || \
    echo "  Already allowlisted or failed"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Start the bot:"
echo "  openclaw gateway run"
echo ""
echo "Or as a background daemon:"
echo "  openclaw daemon start"
echo ""
echo "Then open Telegram and ask your bot:"
echo "  'What are my top 5 stores by revenue?'"
echo ""
