/// Jitter, shimmer and HNR from glottal pulse marks — the same quantities
/// Praat reports, computed with the standard pulse-to-pulse definitions.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'pitch.dart';

// Praat's period validity filters for jitter/shimmer.
const _minPeriodS = 0.0001;
const _maxPeriodS = 0.02;
const _maxPeriodFactor = 1.3;
const _maxAmplitudeFactor = 1.6;

class VoiceQualityResult {
  final double? jitterPercent;
  final double? shimmerPercent;
  final double? hnrDb;

  const VoiceQualityResult({
    this.jitterPercent,
    this.shimmerPercent,
    this.hnrDb,
  });
}

VoiceQualityResult analyzeVoiceQuality(
  Float64List x,
  int sr,
  PitchTrack pitch,
) {
  final pulses = _markPulses(x, sr, pitch);
  final (jitter, shimmer) = _jitterShimmer(x, sr, pulses);
  return VoiceQualityResult(
    jitterPercent: jitter,
    shimmerPercent: shimmer,
    hnrDb: _harmonicity(x, sr, pitch),
  );
}

/// Marks one glottal pulse per period through voiced regions.
///
/// Within each voiced run the marker locks onto ONE waveform polarity (the
/// dominant one) and refines every peak to sub-sample precision — otherwise
/// alternating between positive peaks and negative troughs fakes jitter.
List<double> _markPulses(Float64List x, int sr, PitchTrack pitch) {
  final pulses = <double>[];
  final hop = pitch.hopLength;
  var frame = 0;
  while (frame < pitch.frameCount) {
    if (pitch.f0[frame] <= 0) {
      frame++;
      continue;
    }
    // A voiced run [frame, end).
    var end = frame;
    while (end < pitch.frameCount && pitch.f0[end] > 0) {
      end++;
    }
    final regionStart = frame * hop;
    final regionEnd = math.min((end - 1) * hop + pitch.frameLength, x.length);
    if ((end - frame) >= 3) {
      var period = sr / pitch.f0[frame];
      final firstWindowEnd =
          math.min(regionStart + period.round() + 1, regionEnd);
      // Dominant polarity over the first period decides what "a pulse" is.
      var high = 0.0, low = 0.0;
      for (var i = regionStart; i < firstWindowEnd; i++) {
        if (x[i] > high) high = x[i];
        if (x[i] < low) low = x[i];
      }
      final sign = high >= -low ? 1.0 : -1.0;

      var peakIndex = _argmaxSigned(x, sign, regionStart, firstWindowEnd);
      pulses.add(_refinePeak(x, sign, peakIndex));
      while (true) {
        final f0 = pitch.f0At(peakIndex);
        if (f0 <= 0) break;
        period = sr / f0;
        final searchStart = peakIndex + (0.8 * period).round();
        final searchEnd =
            math.min(peakIndex + (1.25 * period).round(), regionEnd);
        if (searchStart >= searchEnd) break;
        peakIndex = _argmaxSigned(x, sign, searchStart, searchEnd);
        pulses.add(_refinePeak(x, sign, peakIndex));
      }
    }
    frame = end;
  }
  return pulses;
}

int _argmaxSigned(Float64List x, double sign, int start, int end) {
  var best = start;
  var bestValue = double.negativeInfinity;
  for (var i = start; i < end; i++) {
    final value = x[i] * sign;
    if (value > bestValue) {
      bestValue = value;
      best = i;
    }
  }
  return best;
}

/// Parabolic interpolation around a sample peak → fractional peak position.
double _refinePeak(Float64List x, double sign, int index) {
  if (index <= 0 || index >= x.length - 1) return index.toDouble();
  final left = x[index - 1] * sign;
  final mid = x[index] * sign;
  final right = x[index + 1] * sign;
  final denominator = left - 2 * mid + right;
  if (denominator.abs() < 1e-12) return index.toDouble();
  final delta = 0.5 * (left - right) / denominator;
  return delta.abs() < 1 ? index + delta : index.toDouble();
}

(double?, double?) _jitterShimmer(Float64List x, int sr, List<double> pulses) {
  if (pulses.length < 6) return (null, null);

  final periods = <double>[];
  final amplitudes = <double>[];
  for (var i = 0; i < pulses.length - 1; i++) {
    periods.add((pulses[i + 1] - pulses[i]) / sr);
    var high = -2.0, low = 2.0;
    final from = pulses[i].round();
    final to = math.min(pulses[i + 1].round(), x.length);
    for (var k = from; k < to; k++) {
      if (x[k] > high) high = x[k];
      if (x[k] < low) low = x[k];
    }
    amplitudes.add(high - low);
  }

  bool validPeriod(double t) => t >= _minPeriodS && t <= _maxPeriodS;
  bool validPair(double a, double b) =>
      validPeriod(a) &&
      validPeriod(b) &&
      math.max(a, b) / math.min(a, b) <= _maxPeriodFactor;

  var jitterSum = 0.0, jitterCount = 0;
  var periodSum = 0.0, periodCount = 0;
  var shimmerSum = 0.0, shimmerCount = 0;
  var amplitudeSum = 0.0, amplitudeCount = 0;
  for (var i = 0; i < periods.length; i++) {
    if (validPeriod(periods[i])) {
      periodSum += periods[i];
      periodCount++;
      amplitudeSum += amplitudes[i];
      amplitudeCount++;
    }
    if (i == 0) continue;
    if (validPair(periods[i - 1], periods[i])) {
      jitterSum += (periods[i] - periods[i - 1]).abs();
      jitterCount++;
      final ratio = math.max(amplitudes[i], amplitudes[i - 1]) /
          math.max(1e-12, math.min(amplitudes[i], amplitudes[i - 1]));
      if (ratio <= _maxAmplitudeFactor) {
        shimmerSum += (amplitudes[i] - amplitudes[i - 1]).abs();
        shimmerCount++;
      }
    }
  }
  if (jitterCount < 5 || periodCount == 0) return (null, null);

  final meanPeriod = periodSum / periodCount;
  final jitter = (jitterSum / jitterCount) / meanPeriod * 100;
  double? shimmer;
  if (shimmerCount >= 5 && amplitudeCount > 0) {
    final meanAmplitude = amplitudeSum / amplitudeCount;
    if (meanAmplitude > 1e-9) {
      shimmer = (shimmerSum / shimmerCount) / meanAmplitude * 100;
    }
  }
  return (jitter, shimmer);
}

/// Mean HNR (dB) over voiced frames, from the normalized autocorrelation at
/// the period lag: HNR = 10·log10(r / (1 − r)).
double? _harmonicity(Float64List x, int sr, PitchTrack pitch) {
  var sum = 0.0, count = 0;
  for (var i = 0; i < pitch.frameCount; i++) {
    final f0 = pitch.f0[i];
    if (f0 <= 0) continue;
    final lag = (sr / f0).round();
    final start = i * pitch.hopLength;
    final length = pitch.frameLength - lag;
    if (length < lag) continue;
    var dot = 0.0, energyA = 0.0, energyB = 0.0;
    for (var k = 0; k < length; k++) {
      final a = x[start + k], b = x[start + k + lag];
      dot += a * b;
      energyA += a * a;
      energyB += b * b;
    }
    final denominator = math.sqrt(energyA * energyB);
    if (denominator <= 0) continue;
    final r = dot / denominator;
    if (r <= 0 || r >= 1) continue;
    sum += (10 * math.log(r / (1 - r)) / math.ln10).clamp(-10.0, 40.0);
    count++;
  }
  return count > 0 ? sum / count : null;
}
