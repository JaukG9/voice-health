"""Voice embeddings for longitudinal comparison.

Uses a pretrained ECAPA-TDNN speaker encoder (SpeechBrain) when it is
installed. Otherwise it falls back to an MFCC-statistics vector, so the
pipeline stays fully functional with the lightweight default install.
"""

import threading

import numpy as np

from ..config import BASE_DIR
from .dsp import mfcc

_lock = threading.Lock()
_encoder = None
_backend = None


def get_embedding(audio: np.ndarray, sr: int) -> tuple[list[float], str]:
    """Return (unit-length embedding vector, backend name)."""
    encoder, backend = _load_encoder()
    if encoder is not None:
        import torch

        with torch.no_grad():
            batch = torch.tensor(audio, dtype=torch.float32).unsqueeze(0)
            embedding = encoder.encode_batch(batch).squeeze().cpu().numpy()
    else:
        embedding = _mfcc_embedding(audio, sr)
    embedding = embedding / (np.linalg.norm(embedding) + 1e-10)
    return [round(float(v), 5) for v in embedding], backend


def _load_encoder():
    global _encoder, _backend
    with _lock:
        if _backend is None:
            try:
                from speechbrain.inference.speaker import EncoderClassifier

                _encoder = EncoderClassifier.from_hparams(
                    source="speechbrain/spkrec-ecapa-voxceleb",
                    savedir=str(BASE_DIR / "pretrained_models" / "spkrec-ecapa-voxceleb"),
                )
                _backend = "ecapa-tdnn"
            except Exception:
                _encoder = None
                _backend = "mfcc-stats"
    return _encoder, _backend


def _mfcc_embedding(audio: np.ndarray, sr: int) -> np.ndarray:
    coefficients = mfcc(audio, sr, n_mfcc=20, n_mels=40)
    delta = np.gradient(coefficients, axis=0)
    return np.concatenate(
        [coefficients.mean(axis=0), coefficients.std(axis=0), delta.mean(axis=0)]
    )
