"""Speech-to-text via faster-whisper — runs locally on CPU, no API cost."""

import threading

import numpy as np

from ..config import WHISPER_MODEL

_lock = threading.Lock()
_model = None


def get_model():
    """Lazily load Whisper once. The first call downloads the model (~75 MB for 'base')."""
    global _model
    with _lock:
        if _model is None:
            from faster_whisper import WhisperModel

            _model = WhisperModel(WHISPER_MODEL, device="cpu", compute_type="int8")
    return _model


def transcribe(audio: np.ndarray) -> dict:
    """Return transcript, overall confidence and per-word timestamps."""
    segments, _info = get_model().transcribe(
        audio,
        language="en",
        beam_size=5,
        word_timestamps=True,
        vad_filter=True,
    )
    words = []
    for segment in segments:
        for word in segment.words or []:
            words.append(
                {
                    "word": word.word.strip(),
                    "start": round(word.start, 3),
                    "end": round(word.end, 3),
                    "probability": round(word.probability, 3),
                }
            )
    transcript = " ".join(w["word"] for w in words)
    confidence = round(float(np.mean([w["probability"] for w in words])), 3) if words else 0.0
    return {"transcript": transcript, "confidence": confidence, "words": words}
