/// Longitudinal comparison against the user's own history — the Dart port of
/// the backend's trends.py, with identical thresholds and scoring.
library;

import 'dart:math' as math;

import '../models/analysis_result.dart';

const kBaselineSize = 5;

class MetricDef {
  final String key;
  final String label;
  final String unit;
  final String kind; // 'rel' = fractional change vs baseline, 'abs' = delta
  final double threshold; // changes below this are considered stable
  final String adverse; // direction that is a concern: 'up', 'down', 'none'

  const MetricDef(
    this.key,
    this.label,
    this.unit,
    this.kind,
    this.threshold,
    this.adverse,
  );
}

const speechMetricDefs = [
  MetricDef('speech_rate_wpm', 'speech rate', 'wpm', 'rel', 0.10, 'down'),
  MetricDef(
      'articulation_rate_wpm', 'articulation rate', 'wpm', 'rel', 0.10, 'down'),
  MetricDef(
      'avg_pause_duration_s', 'average pause duration', 's', 'rel', 0.25, 'up'),
  MetricDef(
      'pauses_per_minute', 'pause frequency', 'per minute', 'rel', 0.25, 'up'),
  MetricDef('mean_pitch_hz', 'average pitch', 'Hz', 'rel', 0.10, 'none'),
  MetricDef('pitch_variability_semitones', 'pitch variability', 'semitones',
      'rel', 0.30, 'down'),
  MetricDef('mean_volume_db', 'speaking volume', 'dB', 'abs', 3.0, 'down'),
  MetricDef(
      'jitter_percent', 'jitter (voice steadiness)', '%', 'rel', 0.30, 'up'),
  MetricDef('shimmer_percent', 'shimmer (loudness steadiness)', '%', 'rel',
      0.30, 'up'),
  MetricDef('hnr_db', 'voice clarity (HNR)', 'dB', 'abs', 2.0, 'down'),
  MetricDef('tremor_index', 'voice tremor', '', 'abs', 0.08, 'up'),
  MetricDef(
      'rhythm_variability', 'speech rhythm variability', '', 'abs', 0.10, 'up'),
];

/// For a sustained vowel, steadiness flips meaning: on a held note MORE pitch
/// variation is the concern, and shorter phonation suggests reduced breath
/// support.
const vowelMetricDefs = [
  MetricDef('duration_s', 'phonation time', 's', 'rel', 0.15, 'down'),
  MetricDef('mean_pitch_hz', 'average pitch', 'Hz', 'rel', 0.10, 'none'),
  MetricDef('pitch_variability_semitones', 'pitch variation', 'semitones',
      'rel', 0.30, 'up'),
  MetricDef('mean_volume_db', 'loudness', 'dB', 'abs', 3.0, 'down'),
  MetricDef(
      'jitter_percent', 'jitter (voice steadiness)', '%', 'rel', 0.30, 'up'),
  MetricDef('shimmer_percent', 'shimmer (loudness steadiness)', '%', 'rel',
      0.30, 'up'),
  MetricDef('hnr_db', 'voice clarity (HNR)', 'dB', 'abs', 2.0, 'down'),
  MetricDef('tremor_index', 'voice tremor', '', 'abs', 0.08, 'up'),
];

List<MetricDef> metricDefsFor(String recordingType) =>
    recordingType == 'sustained_vowel' ? vowelMetricDefs : speechMetricDefs;

class TrendResult {
  final String status; // first_recording | baseline_building | ok
  final int nHistory;
  final int? stabilityScore;
  final double? baselineSimilarity;
  final List<String> findings;

  const TrendResult({
    required this.status,
    required this.nHistory,
    required this.stabilityScore,
    required this.baselineSimilarity,
    required this.findings,
  });
}

/// Compare the newest recording to the personal baseline for its check type.
/// [history] must contain only recordings of the same type, oldest first.
TrendResult compareToHistory({
  required Map<String, double?> metrics,
  required List<double> embedding,
  required List<AnalysisResult> history,
  required String recordingType,
}) {
  if (history.isEmpty) {
    return const TrendResult(
      status: 'first_recording',
      nHistory: 0,
      stabilityScore: null,
      baselineSimilarity: null,
      findings: [],
    );
  }

  final baselineRows = history.sublist(0, math.min(kBaselineSize, history.length));
  final findings = <String>[];
  final deviations = <double>[];

  for (final def in metricDefsFor(recordingType)) {
    final current = metrics[def.key];
    final baseline = _meanOf(baselineRows, def.key);
    if (current == null || baseline == null) continue;

    final double change;
    if (def.kind == 'rel') {
      if (baseline.abs() < 1e-6) continue;
      change = (current - baseline) / baseline.abs();
    } else {
      change = current - baseline;
    }

    deviations.add(math.min(change.abs() / def.threshold, 4.0));
    if (change.abs() > def.threshold) {
      final direction = change > 0 ? 'up' : 'down';
      final improved = def.adverse != 'none' && direction != def.adverse;
      findings.add(_describe(def, change, improved: improved));
    }
  }

  final baselineSimilarity = _similarity(embedding, baselineRows);
  return TrendResult(
    status: history.length < 3 ? 'baseline_building' : 'ok',
    nHistory: history.length,
    stabilityScore: _stabilityScore(deviations, baselineSimilarity),
    baselineSimilarity: baselineSimilarity,
    findings: findings,
  );
}

double? _meanOf(List<AnalysisResult> rows, String key) {
  var sum = 0.0, count = 0;
  for (final row in rows) {
    final value = row.metrics[key];
    if (value != null) {
      sum += value;
      count++;
    }
  }
  return count > 0 ? sum / count : null;
}

String _describe(MetricDef def, double change, {required bool improved}) {
  final direction = change > 0 ? 'higher' : 'lower';
  final String amount;
  if (def.kind == 'rel') {
    amount = '${(change.abs() * 100).toStringAsFixed(0)}%';
  } else {
    final magnitude = change.abs();
    final digits = magnitude >= 100
        ? magnitude.toStringAsFixed(0)
        : magnitude.toStringAsPrecision(2);
    amount = '$digits ${def.unit}'.trim();
  }
  var sentence = 'Your ${def.label} is about $amount $direction than your '
      'baseline.';
  if (improved) sentence += ' This is a change in a positive direction.';
  return sentence;
}

/// Mean cosine similarity between the new embedding and each baseline row's.
double? _similarity(List<double> embedding, List<AnalysisResult> rows) {
  var sum = 0.0, count = 0;
  for (final row in rows) {
    final other = row.embedding;
    if (other == null || other.length != embedding.length) continue;
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < embedding.length; i++) {
      dot += embedding[i] * other[i];
      normA += embedding[i] * embedding[i];
      normB += other[i] * other[i];
    }
    sum += dot / (math.sqrt(normA) * math.sqrt(normB) + 1e-10);
    count++;
  }
  return count > 0 ? sum / count : null;
}

/// 0-100 heuristic identical to the backend: each metric contributes 1.0
/// while within its stability threshold, decaying to 0 at four times the
/// threshold; embedding similarity is blended in when available.
int? _stabilityScore(List<double> deviations, double? baselineSimilarity) {
  if (deviations.isEmpty) return null;
  var metricComponent = 0.0;
  for (final d in deviations) {
    metricComponent += math.max(0, 1 - math.max(0, d - 1) / 3);
  }
  metricComponent /= deviations.length;
  if (baselineSimilarity == null) return (100 * metricComponent).round();
  final embeddingComponent =
      ((baselineSimilarity - 0.6) / 0.4).clamp(0.0, 1.0);
  return (100 * (0.6 * metricComponent + 0.4 * embeddingComponent)).round();
}
