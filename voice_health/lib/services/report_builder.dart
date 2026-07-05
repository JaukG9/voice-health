import 'package:intl/intl.dart';

import '../models/analysis_result.dart';
import 'app_store.dart';

/// Builds a plain-text report of the full history, suitable for pasting
/// into an email or printing for a clinician.
String buildClinicianReport(AppStore store) {
  final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final history = store.history;
  final buffer = StringBuffer()
    ..writeln('NEUROVOICE AI — SPEECH MONITORING REPORT')
    ..writeln('Generated: ${dateFormat.format(DateTime.now())}')
    ..writeln(store.displayName.isEmpty
        ? 'User ID: ${store.userId.substring(0, 8)}'
        : 'Name: ${store.displayName}')
    ..writeln('Recordings: ${history.length} over ${store.daysTracked} day(s)')
    ..writeln();

  if (history.isEmpty) {
    buffer.writeln('No recordings yet.');
    return buffer.toString();
  }

  buffer
    ..writeln('LATEST SUMMARY')
    ..writeln(history.last.summary)
    ..writeln()
    ..writeln('METRIC TRENDS (first recording -> latest)');
  for (final metric in kChartMetrics) {
    final values = history
        .map((r) => r.metrics[metric.key])
        .whereType<double>()
        .toList();
    if (values.length < 2) continue;
    buffer.writeln('  ${metric.label}: '
        '${metric.format(values.first)} -> ${metric.format(values.last)}');
  }

  buffer
    ..writeln()
    ..writeln('RECORDING LOG');
  for (final r in history) {
    final score =
        r.stabilityScore == null ? '—' : r.stabilityScore!.round().toString();
    final wpm = r.metrics['speech_rate_wpm']?.toStringAsFixed(0) ?? '—';
    buffer.writeln('  ${dateFormat.format(r.createdAt)}  '
        'stability $score/100, $wpm wpm, ${r.durationS.round()}s');
  }

  buffer
    ..writeln()
    ..writeln('All comparisons are against this user\'s own baseline. '
        'This report tracks change over time and is not a diagnosis.');
  return buffer.toString();
}
