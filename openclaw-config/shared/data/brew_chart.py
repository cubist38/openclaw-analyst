"""
Brewlytics chart helper — import this instead of raw matplotlib.

Usage in chart scripts:
    from brew_chart import plt, sns, pd, connect_db, send

    df = pd.read_sql_query("SELECT ...", connect_db())
    fig, ax = plt.subplots()
    # ... plot ...
    send(fig, "data/my_chart.png", "Caption for Telegram")

send() saves the PNG AND delivers it to Telegram in one call.
No separate send_photo.py step needed.
"""
import os
import sys
import sqlite3
import subprocess

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd

# ── BrewMode theme ──────────────────────────────────────────────
plt.rcParams.update({
    'figure.facecolor': '#1a1a2e',
    'axes.facecolor': '#1a1a2e',
    'text.color': '#f5f0e8',
    'axes.labelcolor': '#f5f0e8',
    'xtick.color': '#f5f0e8',
    'ytick.color': '#f5f0e8',
    'axes.edgecolor': '#3a3a5e',
    'grid.color': '#3a3a5e',
    'figure.figsize': (10, 6),
    'font.size': 11,
})

BREW_CARAMEL = '#d4a574'
BREW_CREAM = '#f5f0e8'
BREW_ESPRESSO = '#8B4513'
BREW_LATTE = '#C4A882'
BREW_MOCHA = '#6B3A2A'
BREW_PALETTE = [BREW_CARAMEL, '#7ecfc0', '#e07b54', '#a78bfa', BREW_LATTE, '#f87171']

DB_PATH = 'data/starbucks_business.db'


def connect_db():
    """Return a connection to the Starbucks database."""
    return sqlite3.connect(DB_PATH)


def send(fig, path, caption=None):
    """Save the figure as PNG and send it to Telegram.

    Args:
        fig: matplotlib Figure object
        path: where to save the PNG (e.g. 'data/my_chart.png')
        caption: optional caption shown below the image in Telegram
    """
    # Save
    fig.tight_layout(rect=[0, 0.03, 1, 1])
    fig.savefig(path, dpi=150, bbox_inches='tight')
    plt.close(fig)
    print(f"Chart saved to {path}")

    # Send via Telegram
    script_dir = os.path.dirname(os.path.abspath(__file__))
    send_photo = os.path.join(script_dir, 'send_photo.py')
    python = os.path.join(script_dir, 'python3')

    # Fall back to the python running this script if symlink doesn't exist
    if not os.path.exists(python):
        python = sys.executable

    cmd = [python, send_photo, path]
    if caption:
        cmd.append(caption)

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.stdout:
            print(result.stdout.strip())
        if result.returncode != 0 and result.stderr:
            print(f"WARNING: send_photo failed: {result.stderr.strip()}", file=sys.stderr)
    except Exception as e:
        print(f"WARNING: Could not send photo: {e}", file=sys.stderr)
