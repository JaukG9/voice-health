/// Patient-friendly summaries, worded identically to the backend's summary.py.
/// Deterministic — no LLM, no cloud, no diagnosis.
library;

import 'trends.dart';

String generateSummary(
  Map<String, double?> metrics,
  TrendResult trends,
  String recordingType,
) {
  final isVowel = recordingType == 'sustained_vowel';

  if (isVowel) {
    if (metrics['mean_pitch_hz'] == null || (metrics['duration_s'] ?? 0) < 3) {
      return "We couldn't detect a steadily held vowel in this recording. "
          "Take a deep breath and hold an 'ahhh' sound for about 10 "
          'seconds, close to the phone.';
    }
  } else if ((metrics['word_count'] ?? 0) < 5) {
    return "We couldn't detect enough clear speech in this recording to "
        'analyze it. Try again in a quiet room, holding the phone about '
        '20 cm from your mouth.';
  }

  final nHistory = trends.nHistory;
  if (nHistory == 0) {
    return 'Great start! This first recording becomes your personal baseline '
        'for this check. Future recordings of the same check will be '
        'compared against it to track how your speech changes over time.';
  }
  if (nHistory < 3) {
    return 'Baseline recording ${nHistory + 1} of 3 complete for this check. '
        'A few more recordings are needed before trends become meaningful — '
        'keep recording daily for the most reliable comparison.';
  }

  final subject = isVowel ? 'voice' : 'speech';
  final score = trends.stabilityScore;
  final String opening;
  if (score == null || score >= 85) {
    opening = 'Your $subject is very consistent with your personal baseline.';
  } else if (score >= 70) {
    opening = 'Your $subject is broadly stable compared to your baseline, '
        'with some small variations.';
  } else if (score >= 50) {
    opening =
        'Some noticeable changes were detected compared to your baseline.';
  } else {
    opening =
        'Several notable changes were detected compared to your baseline.';
  }

  final String detail;
  if (trends.findings.isNotEmpty) {
    detail = trends.findings.take(4).join(' ');
  } else if (isVowel) {
    detail = 'Pitch steadiness, loudness, phonation time and voice quality '
        'all remained within their usual range.';
  } else {
    detail = 'Speech rate, pauses, pitch, volume and voice quality all '
        'remained within their usual range.';
  }

  const closing = 'These observations compare this recording only to your own '
      'previous recordings and are not a medical diagnosis — share them with '
      'your clinician if you have concerns.';
  return '$opening $detail $closing';
}
