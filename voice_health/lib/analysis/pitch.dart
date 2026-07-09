/// Autocorrelation pitch tracker (a light take on Praat/Boersma's method).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

const kPitchFloor = 75.0;
const kPitchCeiling = 500.0;

/// Per-frame fundamental frequency track. f0 of 0 means unvoiced.
class PitchTrack {
  final Float64List f0;
  final int frameLength;
  final int hopLength;

  const PitchTrack(this.f0, this.frameLength, this.hopLength);

  int get frameCount => f0.length;

  List<double> get voiced => [
        for (final value in f0)
          if (value > 0) value,
      ];

  /// f0 at a given sample position, 0 if unvoiced/out of range.
  double f0At(int sample) {
    final frame = (sample / hopLength).floor().clamp(0, f0.length - 1);
    return f0[frame];
  }
}

PitchTrack trackPitch(
  Float64List x,
  int sr, {
  double pitchFloor = kPitchFloor,
  double pitchCeiling = kPitchCeiling,
}) {
  final frameLength = (0.04 * sr).round(); // 3 periods at the 75 Hz floor
  final hopLength = (0.01 * sr).round();
  if (x.length < frameLength) {
    return PitchTrack(Float64List(0), frameLength, hopLength);
  }
  final frameCount = (x.length - frameLength) ~/ hopLength + 1;

  // Silence gate: frames much quieter than the loudest frame are unvoiced.
  final rms = Float64List(frameCount);
  var maxRms = 0.0;
  for (var i = 0; i < frameCount; i++) {
    var sum = 0.0;
    final start = i * hopLength;
    for (var k = start; k < start + frameLength; k++) {
      sum += x[k] * x[k];
    }
    rms[i] = math.sqrt(sum / frameLength);
    if (rms[i] > maxRms) maxRms = rms[i];
  }

  final minLag = math.max(2, (sr / pitchCeiling).floor());
  final maxLag = math.min(frameLength - 2, (sr / pitchFloor).ceil());
  // The FFT only needs to be long enough that circular wrap-around can't
  // contaminate lags up to maxLag.
  var fftSize = 1;
  while (fftSize < frameLength + maxLag + 1) {
    fftSize *= 2;
  }
  final fft = FFT(fftSize);

  final f0 = Float64List(frameCount);
  final buffer = Float64List(fftSize);
  for (var i = 0; i < frameCount; i++) {
    if (rms[i] < 0.05 * maxRms) continue;
    final start = i * hopLength;
    var mean = 0.0;
    for (var k = start; k < start + frameLength; k++) {
      mean += x[k];
    }
    mean /= frameLength;
    buffer.fillRange(0, fftSize, 0);
    for (var k = 0; k < frameLength; k++) {
      buffer[k] = x[start + k] - mean;
    }
    // Autocorrelation via Wiener–Khinchin: irfft(|rfft(x)|^2).
    final spectrum = fft.realFft(buffer);
    for (var b = 0; b < spectrum.length; b++) {
      final re = spectrum[b].x, im = spectrum[b].y;
      spectrum[b] = Float64x2(re * re + im * im, 0);
    }
    final autocorr = fft.realInverseFft(spectrum);
    final r0 = autocorr[0];
    if (r0 <= 0) continue;

    // Best local maximum in the allowed lag range.
    var bestLag = -1;
    var bestValue = 0.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      final value = autocorr[lag] / r0;
      if (autocorr[lag] > autocorr[lag - 1] &&
          autocorr[lag] >= autocorr[lag + 1] &&
          value > bestValue) {
        bestValue = value;
        bestLag = lag;
      }
    }
    if (bestLag < 0 || bestValue < 0.45) continue;

    // Parabolic interpolation around the peak for sub-sample lag precision.
    final left = autocorr[bestLag - 1], mid = autocorr[bestLag];
    final right = autocorr[bestLag + 1];
    final denominator = left - 2 * mid + right;
    var lag = bestLag.toDouble();
    if (denominator.abs() > 1e-12) {
      final delta = 0.5 * (left - right) / denominator;
      if (delta.abs() < 1) lag += delta;
    }
    final frequency = sr / lag;
    if (frequency >= pitchFloor && frequency <= pitchCeiling) {
      f0[i] = frequency;
    }
  }

  return PitchTrack(_medianSmooth(f0), frameLength, hopLength);
}

/// 3-point median filter over voiced frames — removes octave glitches.
Float64List _medianSmooth(Float64List f0) {
  final out = Float64List.fromList(f0);
  for (var i = 1; i < f0.length - 1; i++) {
    final a = f0[i - 1], b = f0[i], c = f0[i + 1];
    if (a > 0 && b > 0 && c > 0) {
      out[i] = math.max(math.min(a, b), math.min(math.max(a, b), c));
    }
  }
  return out;
}
