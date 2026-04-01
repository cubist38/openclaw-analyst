#!/bin/bash
# Install OpenClaw analyst bot configuration
# Usage: bash install.sh
#
# This script:
# 1. Installs Node.js and OpenClaw CLI (if not installed)
# 2. Copies analyst config files into the OpenClaw workspace
# 3. Generates the Starbucks SQLite database
# 4. Adds sqlite3 to the exec allowlist
#
# Prerequisites: run `openclaw configure` first to set up API key and Telegram

set -e

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== OpenClaw Business Analyst Bot Setup ==="
echo ""

# --- Step 1: Check dependencies ---
echo "[1/5] Checking dependencies..."

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

# --- Step 2: Check OpenClaw is configured ---
echo "[2/5] Checking OpenClaw configuration..."

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

# --- Step 3: Copy config files ---
echo "[3/5] Installing analyst configuration files..."

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

# --- Step 4: Generate database (skip if already exists) ---
echo "[4/5] Generating Starbucks business database..."

DB_FILE="$WORKSPACE/data/starbucks_business.db"
if [ -f "$DB_FILE" ]; then
    echo "  Database already exists at $DB_FILE"
    echo "  To regenerate, delete it first: rm \"$DB_FILE\""
else
    python3 "$SCRIPT_DIR/generate_starbucks_db.py"
fi
echo ""

# --- Step 5: Allowlist sqlite3 ---
echo "[5/5] Adding sqlite3 to exec allowlist..."

SQLITE3_PATH="$(which sqlite3)"
openclaw approvals allowlist add "$SQLITE3_PATH" 2>/dev/null && \
    echo "  Allowlisted: $SQLITE3_PATH" || \
    echo "  Already allowlisted or failed — check with: openclaw approvals get"

PYTHON3_PATH="$(which python3)"
openclaw approvals allowlist add "$PYTHON3_PATH" 2>/dev/null && \
    echo "  Allowlisted: $PYTHON3_PATH (for chart generation)" || \
    echo "  Already allowlisted or failed — check with: openclaw approvals get"

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
