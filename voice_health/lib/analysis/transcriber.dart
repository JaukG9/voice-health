import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:whisper_ggml/whisper_ggml.dart';

import 'features.dart';

/// On-device speech-to-text using whisper.cpp (via whisper_ggml).
///
/// The ggml model ships inside the app as an asset and is copied to the
/// app's support directory on first use — no network needed. If the asset
/// isn't bundled (e.g. a fresh clone without the model file), it falls back
/// to a one-time download.
class Transcriber {
  final WhisperModel model;
  final WhisperController _controller = WhisperController();

  Transcriber({this.model = WhisperModel.tinyEn});

  String get _assetPath => 'assets/models/ggml-${model.modelName}.bin';

  Future<bool> get isModelReady async =>
      File(await _controller.getPath(model)).exists();

  /// Makes the model available: bundled asset first, download as fallback.
  Future<void> ensureModel({
    void Function(int received, int total)? onProgress,
  }) async {
    final path = await _controller.getPath(model);
    final file = File(path);
    if (await file.exists()) return;

    try {
      final asset = await rootBundle.load(_assetPath);
      final partial = File('$path.part');
      await partial.writeAsBytes(asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      ));
      await partial.rename(path);
      return;
    } on FlutterError {
      // Asset not bundled — fall through to the network download.
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(model.modelUri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Model download failed (${response.statusCode}).');
      }
      final total = response.contentLength;
      final partial = File('$path.part');
      final sink = partial.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
      await partial.rename(path);
    } finally {
      client.close();
    }
  }

  /// Transcribes a WAV file into words with timestamps.
  Future<List<WordTiming>> transcribe(String audioPath) async {
    final whisper = Whisper(model: model);
    final response = await whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: audioPath,
        language: 'en',
        isNoTimestamps: false,
        splitOnWord: true,
      ),
      modelPath: await _controller.getPath(model),
    );

    final words = <WordTiming>[];
    for (final segment in response.segments ?? const <WhisperTranscribeSegment>[]) {
      words.addAll(wordsFromSegment(
        segment.text,
        segment.fromTs.inMilliseconds / 1000,
        segment.toTs.inMilliseconds / 1000,
      ));
    }
    return words;
  }
}

/// Turns one whisper segment into words.
///
/// With `splitOnWord` each segment is normally a single word, but if
/// whisper.cpp ever returns a multi-word segment the interval is split
/// across the words proportionally to their length, so timing metrics stay
/// sane. Non-speech markers like `[BLANK_AUDIO]` or `(silence)` are dropped.
List<WordTiming> wordsFromSegment(String text, double start, double end) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (RegExp(r'^[\[\(].*[\]\)]$').hasMatch(trimmed)) return const [];

  final tokens =
      trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.length == 1) return [WordTiming(tokens.first, start, end)];

  final totalChars =
      tokens.fold<int>(0, (sum, token) => sum + token.length);
  final duration = end - start;
  final words = <WordTiming>[];
  var cursor = start;
  for (final token in tokens) {
    final wordEnd = cursor + duration * token.length / totalChars;
    words.add(WordTiming(token, cursor, wordEnd));
    cursor = wordEnd;
  }
  return words;
}
