"""End-to-end analysis: audio -> transcript -> features -> embedding -> trends -> summary."""

import uuid
from datetime import datetime, timezone

from ..config import SAMPLE_RATE
from ..database import get_history, insert_recording
from .audio import load_audio
from .embeddings import get_embedding
from .features import extract_features
from .summary import generate_summary
from .transcription import transcribe
from .trends import compare


def analyze_recording(path: str, user_id: str, recording_type: str) -> dict:
    audio = load_audio(path)
    if recording_type == "sustained_vowel":
        # A held "ahhh" has no words — skip transcription entirely.
        transcription = {"transcript": "", "confidence": 0.0, "words": []}
    else:
        transcription = transcribe(audio)
    metrics = extract_features(audio, SAMPLE_RATE, transcription["words"])
    embedding, embedding_backend = get_embedding(audio, SAMPLE_RATE)

    # Baselines are per check type: a held vowel is never compared to a
    # reading passage.
    history = get_history(user_id, recording_type)
    trends = compare(metrics, embedding, history, recording_type)
    summary = generate_summary(metrics, trends, recording_type)

    # Same gates the summary uses: a recording without measurable speech (or
    # a steady vowel) is returned to the user but must not enter the baseline.
    if recording_type == "sustained_vowel":
        usable = (
            metrics.get("mean_pitch_hz") is not None
            and metrics.get("duration_s", 0) >= 3
        )
    else:
        usable = metrics.get("word_count", 0) >= 5

    if usable:
        rec_id, created_at = insert_recording(
            user_id=user_id,
            recording_type=recording_type,
            duration_s=metrics["duration_s"],
            transcript=transcription["transcript"],
            confidence=transcription["confidence"],
            metrics=metrics,
            embedding=embedding,
            stability_score=trends["stability_score"],
            summary=summary,
        )
    else:
        rec_id = uuid.uuid4().hex
        created_at = datetime.now(timezone.utc).isoformat()

    return {
        "usable": usable,
        "id": rec_id,
        "created_at": created_at,
        "recording_type": recording_type,
        "duration_s": metrics["duration_s"],
        "transcript": transcription["transcript"],
        "confidence": transcription["confidence"],
        "metrics": metrics,
        "embedding_backend": embedding_backend,
        "trends": trends,
        "stability_score": trends["stability_score"],
        "summary": summary,
    }
