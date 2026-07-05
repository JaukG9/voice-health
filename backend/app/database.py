"""SQLite storage for per-user recording history."""

import json
import sqlite3
import uuid
from datetime import datetime, timezone

from .config import DB_PATH

_SCHEMA = """
CREATE TABLE IF NOT EXISTS recordings (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL,
    recording_type  TEXT NOT NULL,
    created_at      TEXT NOT NULL,
    duration_s      REAL NOT NULL,
    transcript      TEXT NOT NULL,
    confidence      REAL,
    metrics         TEXT NOT NULL,
    embedding       TEXT,
    stability_score REAL,
    summary         TEXT
);
CREATE INDEX IF NOT EXISTS idx_recordings_user ON recordings (user_id, created_at);
"""


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with _connect() as conn:
        conn.executescript(_SCHEMA)


def insert_recording(
    user_id: str,
    recording_type: str,
    duration_s: float,
    transcript: str,
    confidence: float,
    metrics: dict,
    embedding: list[float] | None,
    stability_score: float | None,
    summary: str,
) -> tuple[str, str]:
    """Store one analyzed recording. Returns (id, created_at)."""
    rec_id = uuid.uuid4().hex
    created_at = datetime.now(timezone.utc).isoformat()
    with _connect() as conn:
        conn.execute(
            "INSERT INTO recordings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                rec_id,
                user_id,
                recording_type,
                created_at,
                duration_s,
                transcript,
                confidence,
                json.dumps(metrics),
                json.dumps(embedding) if embedding is not None else None,
                stability_score,
                summary,
            ),
        )
    return rec_id, created_at


def get_history(user_id: str) -> list[dict]:
    """All recordings for a user, oldest first, with JSON columns decoded."""
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM recordings WHERE user_id = ? ORDER BY created_at",
            (user_id,),
        ).fetchall()
    history = []
    for row in rows:
        item = dict(row)
        item["metrics"] = json.loads(item["metrics"])
        item["embedding"] = json.loads(item["embedding"]) if item["embedding"] else None
        history.append(item)
    return history


def delete_user_data(user_id: str) -> int:
    with _connect() as conn:
        cursor = conn.execute("DELETE FROM recordings WHERE user_id = ?", (user_id,))
    return cursor.rowcount
