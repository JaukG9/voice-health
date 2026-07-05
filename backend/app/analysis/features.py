"""Acoustic feature extraction: timing, pitch, voice quality, volume, tremor.

Metrics that cannot be measured on a given recording (e.g. jitter on an
unvoiced sample) are returned as None and skipped by the trend analysis.
"""

import numpy as np
import parselmouth
from parselmouth.praat import call
from scipy import signal

from ..config import PAUSE_THRESHOLD_S
from .dsp import frame_rms, mfcc

PITCH_FLOOR = 75
PITCH_CEILING = 500


def extract_features(audio: np.ndarray, sr: int, words: list[dict]) -> dict:
    snd = parselmouth.Sound(audio.astype(np.float64), sampling_frequency=sr)
    features = {
        "duration_s": round(len(audio) / sr, 2),
        **_timing_metrics(words),
        **_pitch_metrics(snd),
        **_voice_quality_metrics(snd),
        "mean_volume_db": _mean_volume_db(audio),
        "tremor_index": _tremor_index(audio, sr),
        "mfcc_means": _mfcc_means(audio, sr),
    }
    return _finite(features)


def _timing_metrics(words: list[dict]) -> dict:
    if len(words) < 2:
        return {
            "word_count": len(words),
            "speech_rate_wpm": 0.0,
            "articulation_rate_wpm": 0.0,
            "pause_count": 0,
            "pauses_per_minute": 0.0,
            "avg_pause_duration_s": 0.0,
            "rhythm_variability": None,
            "pronunciation_confidence": words[0]["probability"] if words else None,
        }
    span = max(words[-1]["end"] - words[0]["start"], 0.1)
    gaps = [nxt["start"] - cur["end"] for cur, nxt in zip(words, words[1:])]
    pauses = [g for g in gaps if g > PAUSE_THRESHOLD_S]
    speaking_time = max(span - sum(pauses), 0.1)
    durations = [w["end"] - w["start"] for w in words]
    mean_duration = float(np.mean(durations))
    return {
        "word_count": len(words),
        "speech_rate_wpm": round(len(words) / span * 60, 1),
        "articulation_rate_wpm": round(len(words) / speaking_time * 60, 1),
        "pause_count": len(pauses),
        "pauses_per_minute": round(len(pauses) / span * 60, 2),
        "avg_pause_duration_s": round(float(np.mean(pauses)), 3) if pauses else 0.0,
        "rhythm_variability": round(float(np.std(durations)) / mean_duration, 3) if mean_duration > 0 else None,
        "pronunciation_confidence": round(float(np.mean([w["probability"] for w in words])), 3),
    }


def _pitch_metrics(snd: parselmouth.Sound) -> dict:
    pitch = snd.to_pitch(time_step=0.01, pitch_floor=PITCH_FLOOR, pitch_ceiling=PITCH_CEILING)
    frequencies = pitch.selected_array["frequency"]
    voiced = frequencies[frequencies > 0]
    if voiced.size < 10:
        return {"mean_pitch_hz": None, "pitch_variability_semitones": None}
    mean_hz = float(np.mean(voiced))
    semitones = 12 * np.log2(voiced / mean_hz)
    return {
        "mean_pitch_hz": round(mean_hz, 1),
        "pitch_variability_semitones": round(float(np.std(semitones)), 2),
    }


def _voice_quality_metrics(snd: parselmouth.Sound) -> dict:
    try:
        point_process = call(snd, "To PointProcess (periodic, cc)", PITCH_FLOOR, PITCH_CEILING)
        jitter = call(point_process, "Get jitter (local)", 0, 0, 0.0001, 0.02, 1.3) * 100
        shimmer = call([snd, point_process], "Get shimmer (local)", 0, 0, 0.0001, 0.02, 1.3, 1.6) * 100
        harmonicity = call(snd, "To Harmonicity (cc)", 0.01, PITCH_FLOOR, 0.1, 1.0)
        hnr = call(harmonicity, "Get mean", 0, 0)
        return {
            "jitter_percent": round(float(jitter), 2),
            "shimmer_percent": round(float(shimmer), 2),
            "hnr_db": round(float(hnr), 1),
        }
    except Exception:
        return {"jitter_percent": None, "shimmer_percent": None, "hnr_db": None}


def _mean_volume_db(audio: np.ndarray) -> float | None:
    """Mean level (dBFS) of the louder frames, so silence doesn't drag it down."""
    rms = frame_rms(audio, frame_length=2048, hop_length=512)
    active = rms[rms > np.max(rms) * 0.1]
    if active.size == 0:
        return None
    return round(float(np.mean(20 * np.log10(active + 1e-10))), 1)


def _tremor_index(audio: np.ndarray, sr: int) -> float | None:
    """Share of amplitude-envelope modulation in the 3-12 Hz band, where
    pathological voice tremor typically appears, relative to 0.5-20 Hz."""
    hop = sr // 100  # 100 Hz envelope
    envelope = frame_rms(audio, frame_length=hop * 4, hop_length=hop)
    if envelope.size < 64:
        return None
    envelope = envelope - np.mean(envelope)
    frequencies, power = signal.welch(envelope, fs=100, nperseg=min(256, envelope.size))
    total = float(power[(frequencies >= 0.5) & (frequencies <= 20)].sum())
    tremor = float(power[(frequencies >= 3) & (frequencies <= 12)].sum())
    if total <= 0:
        return None
    return round(tremor / total, 3)


def _mfcc_means(audio: np.ndarray, sr: int) -> list[float]:
    coefficients = mfcc(audio, sr, n_mfcc=13)
    return [round(float(v), 2) for v in coefficients.mean(axis=0)]


def _finite(features: dict) -> dict:
    """Replace NaN/inf with None so the output is always valid JSON."""
    cleaned = {}
    for key, value in features.items():
        if isinstance(value, float) and not np.isfinite(value):
            cleaned[key] = None
        elif isinstance(value, list):
            cleaned[key] = [v if np.isfinite(v) else None for v in value]
        else:
            cleaned[key] = value
    return cleaned
