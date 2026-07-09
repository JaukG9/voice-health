/// MFCC-statistics voice embedding — the same fallback the backend uses, so
/// longitudinal similarity works identically on-device.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';

List<double> mfccStatsEmbedding(Float64List x, int sr) {
  final frames = mfccFrames(x, sr, nMfcc: 20, nMels: 40);
  final mean = columnMean(frames);
  final std = columnStd(frames);
  final deltaMean = columnMean(gradientRows(frames));

  final embedding = <double>[...mean, ...std, ...deltaMean];
  var norm = 0.0;
  for (final v in embedding) {
    norm += v * v;
  }
  norm = math.sqrt(norm) + 1e-10;
  return [for (final v in embedding) v / norm];
}
