import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_health/analysis/embedding.dart';
import 'package:voice_health/analysis/features.dart';
import 'package:voice_health/analysis/summary.dart';
import 'package:voice_health/analysis/trends.dart';
import 'package:voice_health/models/analysis_result.dart';

/// Synthetic sustained "ahh": 9.5 s at 120 Hz with slight 5.2 Hz vibrato and
/// six harmonics — the same signal the backend was validated against.
Float64List _syntheticVowel({int sr = 16000}) {
  final n = (sr * 9.5).toInt();
  final audio = Float64List(n);
  final random = math.Random(0);
  var phase = 0.0;
  var peak = 0.0;
  final raw = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final f0 = 120 * (1 + 0.005 * math.sin(2 * math.pi * 5.2 * t));
    phase += 2 * math.pi * f0 / sr;
    var value = 0.0;
    for (var k = 0; k < 6; k++) {
      value += math.pow(0.5, k) * math.sin((k + 1) * phase);
    }
    raw[i] = value;
    if (value.abs() > peak) peak = value.abs();
  }
  final duration = (n - 1) / sr;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final envelope =
        math.min(1.0, math.min(t / 0.3, (duration - t) / 0.3));
    // Box-Muller gaussian noise, seeded for determinism.
    final noise = math.sqrt(-2 * math.log(random.nextDouble() + 1e-12)) *
        math.cos(2 * math.pi * random.nextDouble());
    audio[i] = 0.3 * raw[i] / peak * envelope + 0.002 * noise;
  }
  return audio;
}

AnalysisResult _historyRow(Map<String, double> metrics, List<double> embedding) {
  return AnalysisResult(
    id: 'row',
    createdAt: DateTime(2026, 7, 1),
    recordingType: 'reading_passage',
    durationS: 30,
    transcript: '',
    confidence: 1,
    metrics: metrics,
    embedding: embedding,
    stabilityScore: null,
    summary: '',
    findings: const [],
  );
}

void main() {
  group('feature extraction on a synthetic 120 Hz vowel', () {
    late Map<String, double?> metrics;

    setUpAll(() {
      metrics = extractFeatures(_syntheticVowel(), 16000, const []);
    });

    test('finds the fundamental frequency', () {
      expect(metrics['mean_pitch_hz'], isNotNull);
      expect(metrics['mean_pitch_hz']!, closeTo(120, 3));
    });

    test('measures low jitter and shimmer on a steady tone', () {
      expect(metrics['jitter_percent'], isNotNull);
      expect(metrics['jitter_percent']!, lessThan(1.5));
      expect(metrics['shimmer_percent'], isNotNull);
      expect(metrics['shimmer_percent']!, lessThan(8));
    });

    test('reports a harmonic (clear) voice', () {
      expect(metrics['hnr_db'], isNotNull);
      expect(metrics['hnr_db']!, greaterThan(8));
    });

    test('produces bounded tremor and volume values', () {
      expect(metrics['tremor_index'], isNotNull);
      expect(metrics['tremor_index']!, inInclusiveRange(0, 1));
      expect(metrics['mean_volume_db']!, lessThan(0));
      expect(metrics['mean_volume_db']!, greaterThan(-40));
      expect(metrics['duration_s'], closeTo(9.5, 0.05));
    });
  });

  test('silence yields no voice metrics', () {
    final metrics = extractFeatures(Float64List(16000 * 2), 16000, const []);
    expect(metrics['mean_pitch_hz'], isNull);
    expect(metrics['mean_volume_db'], isNull);
    expect(metrics['jitter_percent'], isNull);
  });

  test('timing metrics from word timestamps', () {
    const words = [
      WordTiming('one', 0.0, 0.3),
      WordTiming('two', 0.4, 0.7),
      WordTiming('three', 1.2, 1.5), // 0.5 s pause before
      WordTiming('four', 1.6, 1.9),
      WordTiming('five', 2.5, 2.8), // 0.6 s pause before
    ];
    final metrics = extractFeatures(Float64List(16000 * 3), 16000, words);
    expect(metrics['word_count'], 5);
    expect(metrics['speech_rate_wpm']!, closeTo(5 / 2.8 * 60, 0.1));
    expect(metrics['pause_count'], 2);
    expect(metrics['avg_pause_duration_s']!, closeTo(0.55, 0.001));
    expect(metrics['articulation_rate_wpm']!, closeTo(5 / 1.7 * 60, 0.1));
  });

  group('trend comparison', () {
    final baselineMetrics = {
      'speech_rate_wpm': 150.0,
      'avg_pause_duration_s': 0.5,
      'mean_pitch_hz': 120.0,
      'mean_volume_db': -25.0,
      'jitter_percent': 1.0,
      'hnr_db': 15.0,
    };
    final embedding = List<double>.filled(60, 1 / math.sqrt(60));
    final history = [
      for (var i = 0; i < 3; i++) _historyRow(baselineMetrics, embedding),
    ];

    test('no history means first recording', () {
      final trend = compareToHistory(
        metrics: baselineMetrics,
        embedding: embedding,
        history: const [],
        recordingType: 'reading_passage',
      );
      expect(trend.status, 'first_recording');
      expect(trend.stabilityScore, isNull);
    });

    test('identical metrics are perfectly stable', () {
      final trend = compareToHistory(
        metrics: baselineMetrics,
        embedding: embedding,
        history: history,
        recordingType: 'reading_passage',
      );
      expect(trend.status, 'ok');
      expect(trend.stabilityScore, 100);
      expect(trend.findings, isEmpty);
    });

    test('a 20% speech-rate drop is flagged and lowers the score', () {
      final trend = compareToHistory(
        metrics: {...baselineMetrics, 'speech_rate_wpm': 120.0},
        embedding: embedding,
        history: history,
        recordingType: 'reading_passage',
      );
      expect(trend.stabilityScore, lessThan(100));
      expect(trend.findings.single, contains('speech rate'));
      expect(trend.findings.single, contains('lower'));
    });

    test('vowel checks track phonation time instead of speech rate', () {
      final vowelMetrics = {
        'duration_s': 10.0,
        'mean_pitch_hz': 120.0,
        'jitter_percent': 0.5,
      };
      final vowelHistory = [
        for (var i = 0; i < 3; i++)
          AnalysisResult(
            id: '$i',
            createdAt: DateTime(2026, 7, 1),
            recordingType: 'sustained_vowel',
            durationS: 10,
            transcript: '',
            confidence: 1,
            metrics: {...vowelMetrics},
            embedding: embedding,
            stabilityScore: null,
            summary: '',
            findings: const [],
          ),
      ];
      final trend = compareToHistory(
        metrics: {...vowelMetrics, 'duration_s': 6.0}, // -40% phonation
        embedding: embedding,
        history: vowelHistory,
        recordingType: 'sustained_vowel',
      );
      expect(trend.findings.single, contains('phonation time'));
    });
  });

  group('summaries', () {
    const okTrend = TrendResult(
      status: 'ok',
      nHistory: 5,
      stabilityScore: 92,
      baselineSimilarity: 0.99,
      findings: [],
    );

    test('first recording message', () {
      const trend = TrendResult(
        status: 'first_recording',
        nHistory: 0,
        stabilityScore: null,
        baselineSimilarity: null,
        findings: [],
      );
      final text = generateSummary(
          {'word_count': 50, 'duration_s': 30}, trend, 'reading_passage');
      expect(text, contains('personal baseline'));
    });

    test('stable speech message', () {
      final text = generateSummary(
          {'word_count': 50, 'duration_s': 30}, okTrend, 'reading_passage');
      expect(text, contains('very consistent'));
      expect(text, contains('not a medical diagnosis'));
    });

    test('vowel gate catches missing pitch', () {
      final text = generateSummary(
          {'duration_s': 9.0, 'mean_pitch_hz': null}, okTrend,
          'sustained_vowel');
      expect(text, contains('steadily held vowel'));
    });
  });

  test('embedding is unit length and deterministic', () {
    final vowel = _syntheticVowel();
    final a = mfccStatsEmbedding(vowel, 16000);
    final b = mfccStatsEmbedding(vowel, 16000);
    expect(a, hasLength(60));
    final norm = math.sqrt(a.fold<double>(0, (s, v) => s + v * v));
    expect(norm, closeTo(1, 1e-9));
    expect(a, b);
  });
}
