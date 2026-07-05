"""Longitudinal comparison of the newest recording against the user's history.

Every comparison is against the user's OWN baseline (their first recordings),
never against population norms — this tracks change, it does not diagnose.
"""

from dataclasses import dataclass

import numpy as np

from ..config import BASELINE_SIZE, RECENT_WINDOW


@dataclass(frozen=True)
class MetricDef:
    key: str
    label: str
    unit: str
    kind: str  # "rel" = fractional change vs baseline, "abs" = absolute delta
    threshold: float  # changes below this are considered stable
    adverse: str  # direction that is a concern: "up", "down" or "none"


SPEECH_METRICS = [
    MetricDef("speech_rate_wpm", "speech rate", "wpm", "rel", 0.10, "down"),
    MetricDef("articulation_rate_wpm", "articulation rate", "wpm", "rel", 0.10, "down"),
    MetricDef("avg_pause_duration_s", "average pause duration", "s", "rel", 0.25, "up"),
    MetricDef("pauses_per_minute", "pause frequency", "per minute", "rel", 0.25, "up"),
    MetricDef("mean_pitch_hz", "average pitch", "Hz", "rel", 0.10, "none"),
    MetricDef("pitch_variability_semitones", "pitch variability", "semitones", "rel", 0.30, "down"),
    MetricDef("mean_volume_db", "speaking volume", "dB", "abs", 3.0, "down"),
    MetricDef("jitter_percent", "jitter (voice steadiness)", "%", "rel", 0.30, "up"),
    MetricDef("shimmer_percent", "shimmer (loudness steadiness)", "%", "rel", 0.30, "up"),
    MetricDef("hnr_db", "voice clarity (HNR)", "dB", "abs", 2.0, "down"),
    MetricDef("tremor_index", "voice tremor", "", "abs", 0.08, "up"),
    MetricDef("rhythm_variability", "speech rhythm variability", "", "abs", 0.10, "up"),
    MetricDef("pronunciation_confidence", "pronunciation clarity", "", "abs", 0.08, "down"),
]

# For a sustained vowel there are no words to time, and steadiness flips
# meaning: on a held note, MORE pitch variation is the concern, and a shorter
# phonation time suggests reduced breath support.
VOWEL_METRICS = [
    MetricDef("duration_s", "phonation time", "s", "rel", 0.15, "down"),
    MetricDef("mean_pitch_hz", "average pitch", "Hz", "rel", 0.10, "none"),
    MetricDef("pitch_variability_semitones", "pitch variation", "semitones", "rel", 0.30, "up"),
    MetricDef("mean_volume_db", "loudness", "dB", "abs", 3.0, "down"),
    MetricDef("jitter_percent", "jitter (voice steadiness)", "%", "rel", 0.30, "up"),
    MetricDef("shimmer_percent", "shimmer (loudness steadiness)", "%", "rel", 0.30, "up"),
    MetricDef("hnr_db", "voice clarity (HNR)", "dB", "abs", 2.0, "down"),
    MetricDef("tremor_index", "voice tremor", "", "abs", 0.08, "up"),
]


def metric_defs_for(recording_type: str) -> list[MetricDef]:
    return VOWEL_METRICS if recording_type == "sustained_vowel" else SPEECH_METRICS


def compare(
    metrics: dict,
    embedding: list[float],
    history: list[dict],
    recording_type: str = "reading_passage",
) -> dict:
    """Compare current metrics/embedding to the personal baseline and recent
    window. History must contain only recordings of the same type."""
    if not history:
        return {
            "status": "first_recording",
            "n_history": 0,
            "stability_score": None,
            "baseline_similarity": None,
            "recent_similarity": None,
            "comparisons": [],
            "findings": [],
        }

    baseline_rows = history[: min(BASELINE_SIZE, len(history))]
    recent_rows = history[-min(RECENT_WINDOW, len(history)) :]

    comparisons, findings, deviations = [], [], []
    for m in metric_defs_for(recording_type):
        current = metrics.get(m.key)
        baseline = _mean_of(baseline_rows, m.key)
        if current is None or baseline is None:
            continue
        if m.kind == "rel":
            if abs(baseline) < 1e-6:
                continue
            change = (current - baseline) / abs(baseline)
        else:
            change = current - baseline

        stable = abs(change) <= m.threshold
        if stable:
            classification = "stable"
        elif m.adverse == "none":
            classification = "changed"
        elif ("up" if change > 0 else "down") == m.adverse:
            classification = "declined"
        else:
            classification = "improved"

        comparisons.append(
            {
                "metric": m.key,
                "label": m.label,
                "unit": m.unit,
                "current": current,
                "baseline": round(baseline, 3),
                "change": round(change, 3),
                "kind": m.kind,
                "classification": classification,
            }
        )
        deviations.append(min(abs(change) / m.threshold, 4.0))
        if not stable:
            findings.append(_describe(m, change, classification))

    baseline_similarity = _similarity(embedding, baseline_rows)
    recent_similarity = _similarity(embedding, recent_rows)

    return {
        "status": "baseline_building" if len(history) < 3 else "ok",
        "n_history": len(history),
        "stability_score": _stability_score(deviations, baseline_similarity),
        "baseline_similarity": baseline_similarity,
        "recent_similarity": recent_similarity,
        "comparisons": comparisons,
        "findings": findings,
    }


def _mean_of(rows: list[dict], key: str) -> float | None:
    values = [r["metrics"].get(key) for r in rows]
    values = [v for v in values if isinstance(v, (int, float))]
    return float(np.mean(values)) if values else None


def _describe(m: MetricDef, change: float, classification: str) -> str:
    direction = "higher" if change > 0 else "lower"
    if m.kind == "rel":
        amount = f"{abs(change) * 100:.0f}%"
    else:
        amount = f"{abs(change):.2g} {m.unit}".strip()
    sentence = f"Your {m.label} is about {amount} {direction} than your baseline."
    if classification == "improved":
        sentence += " This is a change in a positive direction."
    return sentence


def _similarity(embedding: list[float], rows: list[dict]) -> float | None:
    """Mean cosine similarity between the new embedding and each row's embedding."""
    current = np.asarray(embedding)
    similarities = []
    for row in rows:
        other = row.get("embedding")
        if other and len(other) == len(embedding):
            other = np.asarray(other)
            denominator = np.linalg.norm(current) * np.linalg.norm(other) + 1e-10
            similarities.append(float(np.dot(current, other) / denominator))
    return round(float(np.mean(similarities)), 3) if similarities else None


def _stability_score(deviations: list[float], baseline_similarity: float | None) -> int | None:
    """0-100 heuristic: how consistent is this recording with the personal baseline.

    Each metric contributes 1.0 while within its stability threshold, decaying
    to 0 at four times the threshold; the voice-embedding similarity is blended
    in when available.
    """
    if not deviations:
        return None
    metric_component = float(np.mean([max(0.0, 1 - max(0.0, d - 1) / 3) for d in deviations]))
    if baseline_similarity is None:
        return round(100 * metric_component)
    embedding_component = min(max((baseline_similarity - 0.6) / 0.4, 0.0), 1.0)
    return round(100 * (0.6 * metric_component + 0.4 * embedding_component))
