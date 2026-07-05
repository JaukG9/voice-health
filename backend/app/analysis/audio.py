"""Audio loading, resampling and noise reduction."""

import noisereduce as nr
import numpy as np
import soundfile as sf

from ..config import SAMPLE_RATE
from .dsp import resample

MIN_DURATION_S = 1.0


def load_audio(path: str) -> np.ndarray:
    """Load an audio file as denoised mono float32 at SAMPLE_RATE."""
    audio, sr = sf.read(path, dtype="float32", always_2d=True)
    audio = audio.mean(axis=1)
    if sr != SAMPLE_RATE:
        audio = resample(audio, orig_sr=sr, target_sr=SAMPLE_RATE)
    if len(audio) < MIN_DURATION_S * SAMPLE_RATE:
        raise ValueError("Recording is too short to analyze (under 1 second).")
    if float(np.max(np.abs(audio))) < 1e-4:
        raise ValueError("Recording appears to be silent.")
    denoised = nr.reduce_noise(y=audio, sr=SAMPLE_RATE, stationary=True, prop_decrease=0.75)
    return denoised.astype(np.float32)
