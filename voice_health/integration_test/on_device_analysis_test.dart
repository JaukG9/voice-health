/// On-device end-to-end test: runs the full local analysis pipeline —
/// including whisper.cpp over FFI — on a real device/emulator.
///
/// Run with an attached device:
///   `flutter test integration_test/on_device_analysis_test.dart -d device-id`
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:voice_health/analysis/features.dart';
import 'package:voice_health/analysis/local_analyzer.dart';
import 'package:voice_health/analysis/transcriber.dart';
import 'package:voice_health/models/check_type.dart';
import 'package:voice_health/services/app_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late File wavFile;

  setUpAll(() async {
    await AppStore.instance.init();
    final dir = await getApplicationDocumentsDirectory();
    wavFile = File('${dir.path}/test_vowel.wav');
    await wavFile.writeAsBytes(_pcm16Wav(_syntheticVowel(), 16000));
  });

  testWidgets('full on-device sustained-vowel analysis', (tester) async {
    // The onStatus UI callback must never break the isolate hand-off
    // (regression test for a freeze at "Measuring voice features").
    final result = await LocalAnalyzer()
        .analyze(wavFile, kSustainedVowel, onStatus: (_) {});
    expect(result.recordingType, 'sustained_vowel');
    expect(result.metrics['mean_pitch_hz'], isNotNull);
    expect(result.metrics['mean_pitch_hz']!, closeTo(120, 4));
    expect(result.metrics['jitter_percent']!, lessThan(2));
    expect(result.metrics['duration_s']!, closeTo(9.5, 0.1));
    expect(result.embedding, hasLength(60));
    expect(result.summary, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('whisper.cpp loads the bundled model and runs over FFI',
      (tester) async {
    final transcriber = Transcriber();
    await transcriber.ensureModel();
    expect(await transcriber.isModelReady, isTrue);

    // A hum has no words — the point is that the whole FFI round trip
    // (ffmpeg convert -> whisper.cpp -> JSON response) completes.
    final words = await transcriber.transcribe(wavFile.path);
    expect(words, isA<List<WordTiming>>());
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('real speech produces sane metrics end-to-end', (tester) async {
    // The host serves a spoken Rainbow Passage clip during CI-style runs;
    // skip silently when it isn't there (e.g. run on a real phone).
    final dir = await getApplicationDocumentsDirectory();
    final speechFile = File('${dir.path}/passage.wav');
    try {
      final client = HttpClient();
      final request = await client
          .getUrl(Uri.parse('http://10.0.2.2:8765/passage.wav'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close();
      if (response.statusCode != 200) return;
      await response.pipe(speechFile.openWrite());
      client.close();
    } catch (_) {
      return; // no host file server — nothing to test against
    }

    final result = await LocalAnalyzer()
        .analyze(speechFile, kReadingPassage, onStatus: (_) {});
    expect(result.transcript.toLowerCase(), contains('sunlight'));
    expect(result.metrics['word_count']!, greaterThan(40));
    expect(result.metrics['speech_rate_wpm']!, inInclusiveRange(80, 300));
    expect(result.metrics['mean_pitch_hz'], isNotNull);
    expect(result.summary, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Synthetic sustained "ahh": 9.5 s at 120 Hz with slight vibrato.
Float64List _syntheticVowel({int sr = 16000}) {
  final n = (sr * 9.5).toInt();
  final audio = Float64List(n);
  final raw = Float64List(n);
  final random = math.Random(0);
  var phase = 0.0;
  var peak = 0.0;
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
    final envelope = math.min(1.0, math.min(t / 0.3, (duration - t) / 0.3));
    final noise = math.sqrt(-2 * math.log(random.nextDouble() + 1e-12)) *
        math.cos(2 * math.pi * random.nextDouble());
    audio[i] = 0.3 * raw[i] / peak * envelope + 0.002 * noise;
  }
  return audio;
}

/// Minimal PCM16 mono WAV encoder.
Uint8List _pcm16Wav(Float64List samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}
