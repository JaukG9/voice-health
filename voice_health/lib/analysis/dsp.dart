/// Self-contained DSP: framed RMS, Welch PSD, mel-filterbank MFCCs.
///
/// This is a Dart port of the backend's `dsp.py`, so on-device analysis
/// measures the same quantities the same way.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// RMS energy of successive overlapping frames.
Float64List frameRms(Float64List x, int frameLength, int hopLength) {
  if (x.isEmpty) return Float64List.fromList([0]);
  if (x.length < frameLength) {
    var sum = 0.0;
    for (final v in x) {
      sum += v * v;
    }
    return Float64List.fromList([math.sqrt(sum / x.length)]);
  }
  final count = (x.length - frameLength) ~/ hopLength + 1;
  final out = Float64List(count);
  for (var i = 0; i < count; i++) {
    final start = i * hopLength;
    var sum = 0.0;
    for (var k = start; k < start + frameLength; k++) {
      sum += x[k] * x[k];
    }
    out[i] = math.sqrt(sum / frameLength);
  }
  return out;
}

/// Welch power spectral density with 50% overlapping Hann segments.
/// Returns frequencies and PSD values (one-sided).
({Float64List freqs, Float64List psd}) welch(
  Float64List x,
  double fs, {
  int nperseg = 256,
}) {
  final segment = math.min(nperseg, x.length);
  final step = math.max(1, segment ~/ 2);
  final fft = FFT(segment);
  final window = Float64List(segment);
  var windowPower = 0.0;
  for (var k = 0; k < segment; k++) {
    window[k] = 0.5 - 0.5 * math.cos(2 * math.pi * k / segment);
    windowPower += window[k] * window[k];
  }
  final bins = segment ~/ 2 + 1;
  final psd = Float64List(bins);
  var segments = 0;
  for (var start = 0; start + segment <= x.length; start += step) {
    var mean = 0.0;
    for (var k = 0; k < segment; k++) {
      mean += x[start + k];
    }
    mean /= segment;
    final buffer = Float64List(segment);
    for (var k = 0; k < segment; k++) {
      buffer[k] = (x[start + k] - mean) * window[k];
    }
    final spectrum = fft.realFft(buffer);
    for (var b = 0; b < bins; b++) {
      final re = spectrum[b].x, im = spectrum[b].y;
      var power = (re * re + im * im) / (fs * windowPower);
      if (b != 0 && b != segment ~/ 2) power *= 2; // one-sided
      psd[b] += power;
    }
    segments++;
  }
  if (segments > 0) {
    for (var b = 0; b < bins; b++) {
      psd[b] /= segments;
    }
  }
  final freqs = Float64List(bins);
  for (var b = 0; b < bins; b++) {
    freqs[b] = b * fs / segment;
  }
  return (freqs: freqs, psd: psd);
}

/// MFCC frames (each [nMfcc] long) via the standard mel-filterbank pipeline.
List<Float64List> mfccFrames(
  Float64List x,
  int sr, {
  int nMfcc = 13,
  int nMels = 26,
  int frameLength = 400,
  int hopLength = 160,
  int nFft = 512,
}) {
  var signal = x;
  if (signal.length < frameLength) {
    signal = Float64List(frameLength)..setRange(0, x.length, x);
  }
  final window = Float64List(frameLength);
  for (var k = 0; k < frameLength; k++) {
    window[k] = 0.54 - 0.46 * math.cos(2 * math.pi * k / (frameLength - 1));
  }
  final bank = _melFilterbank(sr, nFft, nMels);
  final dct = _dctMatrix(nMfcc, nMels);
  final fft = FFT(nFft);
  final bins = nFft ~/ 2 + 1;

  final frameCount = (signal.length - frameLength) ~/ hopLength + 1;
  final frames = <Float64List>[];
  final buffer = Float64List(nFft);
  for (var i = 0; i < frameCount; i++) {
    buffer.fillRange(0, nFft, 0);
    final start = i * hopLength;
    for (var k = 0; k < frameLength; k++) {
      buffer[k] = signal[start + k] * window[k];
    }
    final spectrum = fft.realFft(buffer);
    final power = Float64List(bins);
    for (var b = 0; b < bins; b++) {
      final re = spectrum[b].x, im = spectrum[b].y;
      power[b] = (re * re + im * im) / nFft;
    }
    final logMel = Float64List(nMels);
    for (var m = 0; m < nMels; m++) {
      var energy = 0.0;
      for (var b = 0; b < bins; b++) {
        energy += power[b] * bank[m][b];
      }
      logMel[m] = math.log(energy + 1e-10);
    }
    final coefficients = Float64List(nMfcc);
    for (var k = 0; k < nMfcc; k++) {
      var sum = 0.0;
      for (var m = 0; m < nMels; m++) {
        sum += logMel[m] * dct[k][m];
      }
      coefficients[k] = sum;
    }
    frames.add(coefficients);
  }
  return frames;
}

List<Float64List> _melFilterbank(int sr, int nFft, int nMels) {
  double toMel(double hz) => 2595 * math.log(1 + hz / 700) / math.ln10;
  double toHz(double mel) => 700 * (math.pow(10, mel / 2595) - 1);

  final maxMel = toMel(sr / 2);
  final bins = List<int>.generate(nMels + 2, (i) {
    final mel = maxMel * i / (nMels + 1);
    return ((nFft + 1) * toHz(mel) / sr).floor();
  });
  final bank = List.generate(nMels, (_) => Float64List(nFft ~/ 2 + 1));
  for (var i = 0; i < nMels; i++) {
    final left = bins[i], center = bins[i + 1], right = bins[i + 2];
    for (var j = left; j < center && j < bank[i].length; j++) {
      bank[i][j] = (j - left) / (center - left);
    }
    for (var j = center; j < right && j < bank[i].length; j++) {
      bank[i][j] = (right - j) / (right - center);
    }
  }
  return bank;
}

/// DCT-II matrix with 'ortho' normalization (matches scipy.fft.dct).
List<Float64List> _dctMatrix(int nOut, int nIn) {
  final matrix = List.generate(nOut, (_) => Float64List(nIn));
  for (var k = 0; k < nOut; k++) {
    final scale = k == 0 ? math.sqrt(1 / nIn) : math.sqrt(2 / nIn);
    for (var n = 0; n < nIn; n++) {
      matrix[k][n] = scale * math.cos(math.pi * k * (2 * n + 1) / (2 * nIn));
    }
  }
  return matrix;
}

/// Column-wise mean over a list of equal-length vectors.
Float64List columnMean(List<Float64List> rows) {
  final out = Float64List(rows.first.length);
  for (final row in rows) {
    for (var i = 0; i < out.length; i++) {
      out[i] += row[i];
    }
  }
  for (var i = 0; i < out.length; i++) {
    out[i] /= rows.length;
  }
  return out;
}

/// Column-wise standard deviation.
Float64List columnStd(List<Float64List> rows) {
  final mean = columnMean(rows);
  final out = Float64List(mean.length);
  for (final row in rows) {
    for (var i = 0; i < out.length; i++) {
      final d = row[i] - mean[i];
      out[i] += d * d;
    }
  }
  for (var i = 0; i < out.length; i++) {
    out[i] = math.sqrt(out[i] / rows.length);
  }
  return out;
}

/// np.gradient along the frame axis: central differences, one-sided at edges.
List<Float64List> gradientRows(List<Float64List> rows) {
  final n = rows.length;
  final width = rows.first.length;
  if (n == 1) return [Float64List(width)];
  return List.generate(n, (i) {
    final out = Float64List(width);
    for (var c = 0; c < width; c++) {
      if (i == 0) {
        out[c] = rows[1][c] - rows[0][c];
      } else if (i == n - 1) {
        out[c] = rows[n - 1][c] - rows[n - 2][c];
      } else {
        out[c] = (rows[i + 1][c] - rows[i - 1][c]) / 2;
      }
    }
    return out;
  });
}
