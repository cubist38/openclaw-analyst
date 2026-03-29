#!/bin/bash
# Create Starbucks business intelligence SQLite database
# Usage: bash create_db.sh

set -e
cd "$(dirname "$0")"
python3 generate_starbucks_db.py
echo ""
echo "Test it: sqlite3 ~/.openclaw/workspace/data/starbucks_business.db '.tables'"
