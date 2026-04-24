#!/bin/bash
# Generate Starbucks business intelligence MySQL init files
# Usage: bash create_db.sh

set -e
cd "$(dirname "$0")"
uv run --with-requirements requirements.txt python generate_starbucks_db.py
echo ""
echo "Generated:"
echo "  database/init/01_schema.sql"
echo "  database/init/02_seed.sql"
echo ""
echo "Start a fresh MySQL volume with:"
echo "  docker compose down -v && docker compose up -d --build"
