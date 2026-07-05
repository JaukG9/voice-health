import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records 16 kHz mono WAV — exactly the format the analysis backend expects.
/// Recordings are kept on the device under documents/recordings/.
class RecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  /// Starts recording. Returns false if microphone permission was denied.
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/recordings');
    await dir.create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(':', '-');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: '${dir.path}/rec_$stamp.wav',
    );
    return true;
  }

  /// Stops recording and returns the file path.
  Future<String?> stop() => _recorder.stop();

  Future<void> cancel() => _recorder.cancel();

  void dispose() => _recorder.dispose();
}
