import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../models/analysis_result.dart';
import '../models/check_type.dart';
import '../services/app_store.dart';
import 'embedding.dart';
import 'features.dart';
import 'summary.dart';
import 'transcriber.dart';
import 'trends.dart';
import 'wav_reader.dart';

class LocalAnalysisException implements Exception {
  final String message;

  const LocalAnalysisException(this.message);

  @override
  String toString() => message;
}

/// Fully on-device analysis: whisper.cpp transcription + Dart DSP.
/// Produces the same [AnalysisResult] shape as the backend, so the rest of
/// the app doesn't care which engine ran.
class LocalAnalyzer {
  final Transcriber transcriber;

  LocalAnalyzer({Transcriber? transcriber})
      : transcriber = transcriber ?? Transcriber();

  Future<AnalysisResult> analyze(
    File audioFile,
    CheckType type, {
    void Function(String status)? onStatus,
  }) async {
    final wav = await readWavFile(audioFile);
    var samples = wav.samples;
    var sampleRate = wav.sampleRate;
    if (sampleRate != 16000) {
      samples = resampleLinear(samples, sampleRate, 16000);
      sampleRate = 16000;
    }
    if (samples.length < sampleRate) {
      throw const LocalAnalysisException(
          'Recording is too short to analyze (under 1 second).');
    }
    var peak = 0.0;
    for (final v in samples) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak < 1e-4) {
      throw const LocalAnalysisException('Recording appears to be silent.');
    }

    // A held "ahhh" has no words — skip transcription entirely.
    var words = const <WordTiming>[];
    if (type.key != 'sustained_vowel') {
      if (!await transcriber.isModelReady) {
        onStatus?.call('Preparing speech model (first run)…');
        await transcriber.ensureModel(onProgress: (received, total) {
          if (total > 0) {
            final percent = (received / total * 100).round();
            onStatus?.call('Downloading speech model… $percent%');
          }
        });
      }
      onStatus?.call('Transcribing on this phone…');
      try {
        words = await transcriber
            .transcribe(audioFile.path)
            .timeout(const Duration(minutes: 5));
      } on TimeoutException {
        throw const LocalAnalysisException(
            'Speech recognition timed out on this device.');
      } catch (e) {
        throw LocalAnalysisException('Speech recognition failed: $e');
      }
    }

    onStatus?.call('Measuring voice features…');
    ({Map<String, double?> metrics, List<double> embedding}) engine;
    try {
      // Feature extraction and the embedding are independent — run them on
      // two isolates in parallel.
      final parts = await Future.wait<Object>([
        _featuresInIsolate(samples, sampleRate, words),
        _embeddingInIsolate(samples, sampleRate),
      ]).timeout(const Duration(minutes: 2));
      engine = (
        metrics: parts[0] as Map<String, double?>,
        embedding: parts[1] as List<double>,
      );
    } on TimeoutException {
      throw const LocalAnalysisException(
          'Voice measurement timed out on this device.');
    } catch (e) {
      if (e is LocalAnalysisException) rethrow;
      throw LocalAnalysisException('Voice measurement failed: $e');
    }

    // Baselines are per check type, same as the backend.
    final history = AppStore.instance.history
        .where((r) => r.recordingType == type.key)
        .toList();
    final trend = compareToHistory(
      metrics: engine.metrics,
      embedding: engine.embedding,
      history: history,
      recordingType: type.key,
    );
    final summary = generateSummary(engine.metrics, trend, type.key);

    // Same gates the summary uses: a recording without measurable speech (or
    // a steady vowel) is shown to the user but must not enter the baseline.
    final usable = type.key == 'sustained_vowel'
        ? engine.metrics['mean_pitch_hz'] != null &&
            (engine.metrics['duration_s'] ?? 0) >= 3
        : (engine.metrics['word_count'] ?? 0) >= 5;

    return AnalysisResult(
      id: _newId(),
      createdAt: DateTime.now(),
      recordingType: type.key,
      durationS: engine.metrics['duration_s'] ?? 0,
      transcript: words.map((w) => w.word).join(' '),
      confidence: 0,
      metrics: {
        for (final entry in engine.metrics.entries)
          if (entry.value != null) entry.key: entry.value!,
      },
      embedding: engine.embedding,
      stabilityScore: trend.stabilityScore?.toDouble(),
      summary: summary,
      findings: trend.findings,
      usable: usable,
    );
  }

  // These MUST stay static methods whose scope holds only sendable values:
  // Isolate.run serializes the closure's surrounding context, and inside
  // analyze() that context includes the onStatus UI callback, which cannot
  // cross isolates.

  static Future<Map<String, double?>> _featuresInIsolate(
          Float64List samples, int sampleRate, List<WordTiming> words) =>
      Isolate.run(() => extractFeatures(samples, sampleRate, words));

  static Future<List<double>> _embeddingInIsolate(
          Float64List samples, int sampleRate) =>
      Isolate.run(() => mfccStatsEmbedding(samples, sampleRate));

  static String _newId() {
    final random = Random().nextInt(1 << 30).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}$random';
  }
}
