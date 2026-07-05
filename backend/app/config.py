"""Central configuration. Every value can be overridden via environment variable."""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# Whisper model size: tiny / base / small / medium. Bigger = more accurate, slower.
WHISPER_MODEL = os.getenv("NEUROVOICE_WHISPER_MODEL", "base")

# SQLite file holding all recording history.
DB_PATH = os.getenv("NEUROVOICE_DB", str(BASE_DIR / "neurovoice.db"))

# All audio is resampled to this rate before analysis.
SAMPLE_RATE = 16000

# A silent gap between words longer than this counts as a pause.
PAUSE_THRESHOLD_S = 0.35

# The first N recordings form the user's personal baseline.
BASELINE_SIZE = 5

# The last N recordings form the "recent" comparison window.
RECENT_WINDOW = 7
