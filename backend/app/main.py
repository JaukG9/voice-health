"""NeuroVoice AI backend — local speech-analysis server.

Run from the backend/ directory:

    uvicorn app.main:app --host 0.0.0.0 --port 8000

Interactive API docs: http://localhost:8000/docs
"""

import os
import tempfile
import threading
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from .analysis.pipeline import analyze_recording
from .analysis.transcription import get_model
from .config import WHISPER_MODEL
from .database import delete_user_data, get_history, init_db

# One analysis at a time keeps memory predictable on a laptop-class machine.
_analysis_lock = threading.Lock()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_db()
    # Warm up Whisper in the background so the first /analyze isn't slow.
    threading.Thread(target=get_model, daemon=True).start()
    yield


app = FastAPI(title="NeuroVoice AI", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "whisper_model": WHISPER_MODEL}


@app.post("/analyze")
def analyze(
    file: UploadFile = File(...),
    user_id: str = Form(...),
    recording_type: str = Form("reading_passage"),
) -> dict:
    suffix = Path(file.filename or "recording.wav").suffix or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(file.file.read())
        tmp_path = tmp.name
    try:
        with _analysis_lock:
            return analyze_recording(tmp_path, user_id, recording_type)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        os.unlink(tmp_path)


@app.get("/history/{user_id}")
def history(user_id: str) -> dict:
    rows = get_history(user_id)
    for row in rows:
        row.pop("embedding", None)  # internal detail, and large
    return {"recordings": rows}


@app.delete("/history/{user_id}")
def delete_history(user_id: str) -> dict:
    return {"deleted": delete_user_data(user_id)}
