/// Acoustic feature extraction — the Dart port of the backend's features.py.
/// Metrics that cannot be measured on a recording are null and are skipped
/// by the trend analysis.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';
import 'pitch.dart';
import 'voice_quality.dart';

const kPauseThresholdS = 0.35;

/// A transcribed word with its position on the recording's timeline.
class WordTiming {
  final String word;
  final double start;
  final double end;

  const WordTiming(this.word, this.start, this.end);
}

Map<String, double?> extractFeatures(
  Float64List x,
  int sr,
  List<WordTiming> words,
) {
  final pitch = trackPitch(x, sr);
  final quality = analyzeVoiceQuality(x, sr, pitch);
  return {
    'duration_s': _round(x.length / sr, 2),
    ..._timingMetrics(words),
    ..._pitchMetrics(pitch),
    'jitter_percent': _round(quality.jitterPercent, 2),
    'shimmer_percent': _round(quality.shimmerPercent, 2),
    'hnr_db': _round(quality.hnrDb, 1),
    'mean_volume_db': _round(_meanVolumeDb(x), 1),
    'tremor_index': _round(_tremorIndex(x, sr), 3),
  };
}

Map<String, double?> _timingMetrics(List<WordTiming> words) {
  if (words.length < 2) {
    return {
      'word_count': words.length.toDouble(),
      'speech_rate_wpm': 0,
      'articulation_rate_wpm': 0,
      'pause_count': 0,
      'pauses_per_minute': 0,
      'avg_pause_duration_s': 0,
      'rhythm_variability': null,
    };
  }
  final span = math.max(words.last.end - words.first.start, 0.1);
  final pauses = <double>[];
  for (var i = 0; i < words.length - 1; i++) {
    final gap = words[i + 1].start - words[i].end;
    if (gap > kPauseThresholdS) pauses.add(gap);
  }
  final pauseTime = pauses.fold(0.0, (a, b) => a + b);
  final speakingTime = math.max(span - pauseTime, 0.1);
  final durations = [for (final w in words) w.end - w.start];
  final meanDuration = durations.reduce((a, b) => a + b) / durations.length;
  var durationVariance = 0.0;
  for (final d in durations) {
    durationVariance += (d - meanDuration) * (d - meanDuration);
  }
  final durationStd = math.sqrt(durationVariance / durations.length);
  return {
    'word_count': words.length.toDouble(),
    'speech_rate_wpm': _round(words.length / span * 60, 1),
    'articulation_rate_wpm': _round(words.length / speakingTime * 60, 1),
    'pause_count': pauses.length.toDouble(),
    'pauses_per_minute': _round(pauses.length / span * 60, 2),
    'avg_pause_duration_s':
        pauses.isEmpty ? 0 : _round(pauseTime / pauses.length, 3),
    'rhythm_variability':
        meanDuration > 0 ? _round(durationStd / meanDuration, 3) : null,
  };
}

Map<String, double?> _pitchMetrics(PitchTrack pitch) {
  final voiced = pitch.voiced;
  if (voiced.length < 10) {
    return {'mean_pitch_hz': null, 'pitch_variability_semitones': null};
  }
  final meanHz = voiced.reduce((a, b) => a + b) / voiced.length;
  var variance = 0.0;
  for (final f in voiced) {
    final semitones = 12 * math.log(f / meanHz) / math.ln2;
    variance += semitones * semitones;
  }
  return {
    'mean_pitch_hz': _round(meanHz, 1),
    'pitch_variability_semitones':
        _round(math.sqrt(variance / voiced.length), 2),
  };
}

/// Mean level (dBFS) of the louder frames, so silence doesn't drag it down.
double? _meanVolumeDb(Float64List x) {
  final rms = frameRms(x, 2048, 512);
  var maxRms = 0.0;
  for (final v in rms) {
    if (v > maxRms) maxRms = v;
  }
  var sum = 0.0, count = 0;
  for (final v in rms) {
    if (v > maxRms * 0.1) {
      sum += 20 * math.log(v + 1e-10) / math.ln10;
      count++;
    }
  }
  return count > 0 ? sum / count : null;
}

/// Share of amplitude-envelope modulation in the 3-12 Hz band, where
/// pathological voice tremor typically appears, relative to 0.5-20 Hz.
double? _tremorIndex(Float64List x, int sr) {
  final hop = sr ~/ 100; // 100 Hz envelope
  final envelope = frameRms(x, hop * 4, hop);
  if (envelope.length < 64) return null;
  var mean = 0.0;
  for (final v in envelope) {
    mean += v;
  }
  mean /= envelope.length;
  final centered = Float64List(envelope.length);
  for (var i = 0; i < envelope.length; i++) {
    centered[i] = envelope[i] - mean;
  }
  final spectrum = welch(centered, 100, nperseg: math.min(256, centered.length));
  var total = 0.0, tremor = 0.0;
  for (var i = 0; i < spectrum.freqs.length; i++) {
    final f = spectrum.freqs[i];
    if (f >= 0.5 && f <= 20) total += spectrum.psd[i];
    if (f >= 3 && f <= 12) tremor += spectrum.psd[i];
  }
  return total > 0 ? tremor / total : null;
}

double? _round(double? value, int decimals) {
  if (value == null || !value.isFinite) return null;
  final factor = math.pow(10, decimals);
  return (value * factor).round() / factor;
}
