import 'dart:io';
import 'dart:typed_data';

/// Decoded audio: mono samples in [-1, 1] at [sampleRate].
class WavData {
  final Float64List samples;
  final int sampleRate;

  const WavData(this.samples, this.sampleRate);

  double get durationS => samples.length / sampleRate;
}

/// Reads a PCM16 RIFF/WAVE file (the format our recorder produces).
Future<WavData> readWavFile(File file) async {
  final bytes = await file.readAsBytes();
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('Not a WAV file.');
  }
  final data = ByteData.sublistView(bytes);

  var channels = 1;
  var sampleRate = 16000;
  var bitsPerSample = 16;
  var offset = 12;
  Float64List? samples;

  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (chunkId == 'fmt ') {
      final format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
      if (format != 1 || bitsPerSample != 16) {
        throw const FormatException('Only PCM16 WAV is supported.');
      }
    } else if (chunkId == 'data') {
      final sampleCount = (chunkSize ~/ 2) ~/ channels;
      samples = Float64List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        var sum = 0.0;
        for (var c = 0; c < channels; c++) {
          sum += data.getInt16(body + (i * channels + c) * 2, Endian.little);
        }
        samples[i] = sum / channels / 32768.0;
      }
    }
    offset = body + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (samples == null) throw const FormatException('WAV has no data chunk.');
  return WavData(samples, sampleRate);
}

/// Linear resampler — a safety net; our recorder already produces 16 kHz.
Float64List resampleLinear(Float64List x, int fromRate, int toRate) {
  if (fromRate == toRate) return x;
  final outLength = (x.length * toRate / fromRate).floor();
  final out = Float64List(outLength);
  for (var i = 0; i < outLength; i++) {
    final position = i * fromRate / toRate;
    final index = position.floor();
    final fraction = position - index;
    final next = index + 1 < x.length ? x[index + 1] : x[index];
    out[i] = x[index] * (1 - fraction) + next * fraction;
  }
  return out;
}
