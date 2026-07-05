"""End-to-end analysis: audio -> transcript -> features -> embedding -> trends -> summary."""

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
    transcription = transcribe(audio)
    metrics = extract_features(audio, SAMPLE_RATE, transcription["words"])
    embedding, embedding_backend = get_embedding(audio, SAMPLE_RATE)

    history = get_history(user_id)
    trends = compare(metrics, embedding, history)
    summary = generate_summary(metrics, trends)

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
    return {
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
