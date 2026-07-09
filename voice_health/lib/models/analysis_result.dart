/// One analyzed recording, as returned by the backend `/analyze` endpoint
/// and cached locally on the device.
class AnalysisResult {
  final String id;
  final DateTime createdAt;
  final String recordingType;
  final double durationS;
  final String transcript;
  final double confidence;
  final Map<String, double> metrics;

  /// Voice embedding, kept only for on-device longitudinal comparison.
  /// Backend-analyzed results don't carry one (the server keeps its own).
  final List<double>? embedding;
  final double? stabilityScore;
  final String summary;
  final List<String> findings;

  const AnalysisResult({
    required this.id,
    required this.createdAt,
    required this.recordingType,
    required this.durationS,
    required this.transcript,
    required this.confidence,
    required this.metrics,
    this.embedding,
    required this.stabilityScore,
    required this.summary,
    required this.findings,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final metrics = <String, double>{};
    (json['metrics'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
      if (value is num) metrics[key] = value.toDouble();
    });
    final trends = json['trends'] as Map<String, dynamic>? ?? {};
    final findings = (trends['findings'] ?? json['findings'] ?? []) as List;
    return AnalysisResult(
      id: json['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      recordingType: json['recording_type'] as String? ?? 'reading_passage',
      durationS: (json['duration_s'] as num? ?? 0).toDouble(),
      transcript: json['transcript'] as String? ?? '',
      confidence: (json['confidence'] as num? ?? 0).toDouble(),
      metrics: metrics,
      embedding: (json['embedding'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      stabilityScore: (json['stability_score'] as num?)?.toDouble(),
      summary: json['summary'] as String? ?? '',
      findings: findings.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'recording_type': recordingType,
        'duration_s': durationS,
        'transcript': transcript,
        'confidence': confidence,
        'metrics': metrics,
        if (embedding != null) 'embedding': embedding,
        'stability_score': stabilityScore,
        'summary': summary,
        'findings': findings,
      };
}

/// Display info for a chartable metric coming from the backend.
class MetricInfo {
  final String key;
  final String label;
  final String unit;
  final int decimals;

  const MetricInfo(this.key, this.label, this.unit, this.decimals);

  String format(double value) =>
      '${value.toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';
}

const kChartMetrics = [
  MetricInfo('speech_rate_wpm', 'Speech rate', 'wpm', 0),
  MetricInfo('mean_pitch_hz', 'Average pitch', 'Hz', 0),
  MetricInfo('avg_pause_duration_s', 'Pause duration', 's', 2),
  MetricInfo('mean_volume_db', 'Volume', 'dB', 1),
  MetricInfo('pitch_variability_semitones', 'Pitch variability', 'st', 1),
  MetricInfo('jitter_percent', 'Jitter', '%', 2),
  MetricInfo('shimmer_percent', 'Shimmer', '%', 2),
  MetricInfo('hnr_db', 'Voice clarity (HNR)', 'dB', 1),
  MetricInfo('tremor_index', 'Tremor', '', 3),
  MetricInfo('pronunciation_confidence', 'Articulation', '', 2),
];

/// Metrics that are meaningful for a sustained vowel — there are no words,
/// so rate/pause/articulation metrics don't apply.
const kVowelMetricKeys = {
  'duration_s',
  'mean_pitch_hz',
  'pitch_variability_semitones',
  'mean_volume_db',
  'jitter_percent',
  'shimmer_percent',
  'hnr_db',
  'tremor_index',
};

/// Chartable metrics for a given check type.
List<MetricInfo> chartMetricsFor(String typeKey) {
  if (typeKey != 'sustained_vowel') return kChartMetrics;
  return [
    const MetricInfo('duration_s', 'Phonation time', 's', 1),
    ...kChartMetrics.where((m) => kVowelMetricKeys.contains(m.key)),
  ];
}
