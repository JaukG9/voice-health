"""Patient-friendly summaries, generated deterministically from the trend data.

No cloud LLM is used (zero cost, zero data sharing) and no diagnosis is made —
the text only describes how this recording compares to the user's own history
for the same type of check.
"""


def generate_summary(
    metrics: dict, trends: dict, recording_type: str = "reading_passage"
) -> str:
    is_vowel = recording_type == "sustained_vowel"

    if is_vowel:
        if metrics.get("mean_pitch_hz") is None or metrics.get("duration_s", 0) < 3:
            return (
                "We couldn't detect a steadily held vowel in this recording. "
                "Take a deep breath and hold an 'ahhh' sound for about 10 "
                "seconds, close to the phone."
            )
    elif metrics.get("word_count", 0) < 5:
        return (
            "We couldn't detect enough clear speech in this recording to analyze it. "
            "Try again in a quiet room, holding the phone about 20 cm from your mouth."
        )

    n_history = trends["n_history"]
    if n_history == 0:
        return (
            "Great start! This first recording becomes your personal baseline "
            "for this check. Future recordings of the same check will be "
            "compared against it to track how your speech changes over time."
        )
    if n_history < 3:
        return (
            f"Baseline recording {n_history + 1} of 3 complete for this check. "
            "A few more recordings are needed before trends become meaningful — "
            "keep recording daily for the most reliable comparison."
        )

    subject = "voice" if is_vowel else "speech"
    score = trends["stability_score"]
    if score is None or score >= 85:
        opening = f"Your {subject} is very consistent with your personal baseline."
    elif score >= 70:
        opening = (
            f"Your {subject} is broadly stable compared to your baseline, "
            "with some small variations."
        )
    elif score >= 50:
        opening = "Some noticeable changes were detected compared to your baseline."
    else:
        opening = "Several notable changes were detected compared to your baseline."

    findings = trends["findings"]
    if findings:
        detail = " ".join(findings[:4])
    elif is_vowel:
        detail = (
            "Pitch steadiness, loudness, phonation time and voice quality all "
            "remained within their usual range."
        )
    else:
        detail = (
            "Speech rate, pauses, pitch, volume and voice quality all remained "
            "within their usual range."
        )

    closing = (
        "These observations compare this recording only to your own previous "
        "recordings and are not a medical diagnosis — share them with your "
        "clinician if you have concerns."
    )
    return f"{opening} {detail} {closing}"
