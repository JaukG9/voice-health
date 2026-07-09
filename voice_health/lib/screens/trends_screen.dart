import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/analysis_result.dart';
import '../models/check_type.dart';
import '../services/app_store.dart';

/// A point in time for one metric.
class _Point {
  final DateTime date;
  final double value;
  const _Point(this.date, this.value);
}

/// Interactive charts of every speech metric over 7/30/90 days or all time.
class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  static const _stabilityKey = '_stability';

  int _rangeDays = 30; // 0 = all time
  String _typeKey = 'reading_passage';
  String _metricKey = _stabilityKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final points = _points();
        return Scaffold(
          appBar: AppBar(title: const Text('Trends')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final type in kCheckTypes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(type.icon, size: 16),
                          label: Text(type.shortTitle),
                          selected: _typeKey == type.key,
                          onSelected: (_) => _selectType(type.key),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7D')),
                  ButtonSegment(value: 30, label: Text('30D')),
                  ButtonSegment(value: 90, label: Text('90D')),
                  ButtonSegment(value: 0, label: Text('All')),
                ],
                selected: {_rangeDays},
                onSelectionChanged: (selection) =>
                    setState(() => _rangeDays = selection.first),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip(_stabilityKey, 'Overall score'),
                    for (final metric in chartMetricsFor(_typeKey))
                      _chip(metric.key, metric.label),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (points.length < 2)
                _emptyState(context)
              else ...[
                SizedBox(height: 260, child: _chart(context, points)),
                const SizedBox(height: 16),
                _changeCard(context, points),
              ],
            ],
          ),
        );
      },
    );
  }

  void _selectType(String typeKey) {
    setState(() {
      _typeKey = typeKey;
      // Reset the metric if it isn't meaningful for the new check type.
      final valid = chartMetricsFor(typeKey).any((m) => m.key == _metricKey);
      if (!valid) _metricKey = _stabilityKey;
    });
  }

  Widget _chip(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _metricKey == key,
        onSelected: (_) => setState(() => _metricKey = key),
      ),
    );
  }

  List<_Point> _points() {
    final cutoff = _rangeDays == 0
        ? null
        : DateTime.now().subtract(Duration(days: _rangeDays));
    final points = <_Point>[];
    for (final result in AppStore.instance.history) {
      if (result.recordingType != _typeKey) continue;
      if (cutoff != null && result.createdAt.isBefore(cutoff)) continue;
      final value = _metricKey == _stabilityKey
          ? result.stabilityScore
          : result.metrics[_metricKey];
      if (value != null) points.add(_Point(result.createdAt, value));
    }
    return points;
  }

  Widget _chart(BuildContext context, List<_Point> points) {
    final scheme = Theme.of(context).colorScheme;
    final first = points.first.date;
    // Seconds-level x resolution: several recordings on one day spread out
    // by their time instead of stacking into a vertical line.
    final spots = [
      for (final point in points)
        FlSpot(point.date.difference(first).inSeconds / 86400.0, point.value),
    ];
    final values = points.map((p) => p.value).toList();
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY).abs() * 0.15 + 0.5;
    minY -= padding;
    maxY += padding;
    final totalDays = spots.last.x <= 0 ? 1.0 : spots.last.x;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Sub-two-day spans label by time of day instead of by date.
              interval: totalDays < 2
                  ? (totalDays / 4).clamp(1 / 24, 1.0)
                  : (totalDays / 4).clamp(1.0, double.infinity),
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  DateFormat(totalDays < 2 ? 'HH:mm' : 'M/d').format(
                      first.add(Duration(seconds: (value * 86400).round()))),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            preventCurveOverShooting: true,
            barWidth: 3,
            color: scheme.primary,
            dotData: FlDotData(show: points.length <= 20),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _changeCard(BuildContext context, List<_Point> points) {
    final info = _metricKey == _stabilityKey
        ? const MetricInfo(_stabilityKey, 'Overall score', '', 0)
        : chartMetricsFor(_typeKey).firstWhere((m) => m.key == _metricKey);
    final first = points.first.value;
    final last = points.last.value;
    final delta = last - first;
    final arrow = delta.abs() < 1e-9 ? '→' : (delta > 0 ? '↑' : '↓');
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        title: Text('${info.label} over this period'),
        subtitle: Text(
          '${info.format(first)}  →  ${info.format(last)}   '
          '($arrow ${info.format(delta.abs())})',
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(Icons.show_chart,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'Record at least two "${checkTypeByKey(_typeKey).title}" checks '
            'in this period to see a trend.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
