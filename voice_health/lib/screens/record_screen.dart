import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../services/api_service.dart';
import '../services/app_store.dart';
import '../services/recorder_service.dart';
import '../widgets/score_ring.dart';

/// The Rainbow Passage — a standard text used in speech assessment, so every
/// recording is directly comparable to the previous ones.
const kReadingPassage =
    'When the sunlight strikes raindrops in the air, they act as a prism and '
    'form a rainbow. The rainbow is a division of white light into many '
    'beautiful colors. These take the shape of a long round arch, with its '
    'path high above, and its two ends apparently beyond the horizon. There '
    'is, according to legend, a boiling pot of gold at one end. People look, '
    'but no one ever finds it. When a man looks for something beyond his '
    'reach, his friends say he is looking for the pot of gold at the end of '
    'the rainbow.';

enum _Phase { idle, recording, recorded, analyzing, done }

/// Daily voice check: read the passage aloud, then send it for analysis.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _recorder = RecorderService();
  final _api = ApiService();

  _Phase _phase = _Phase.idle;
  String? _path;
  AnalysisResult? _result;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.start()) {
      _showError('Microphone permission is required to record.');
      return;
    }
    setState(() {
      _phase = _Phase.recording;
      _elapsed = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _path = path;
      _phase = path == null ? _Phase.idle : _Phase.recorded;
    });
  }

  Future<void> _discard() async {
    if (_path != null) {
      try {
        await File(_path!).delete();
      } catch (_) {}
    }
    setState(() {
      _path = null;
      _phase = _Phase.idle;
    });
  }

  Future<void> _analyze() async {
    setState(() => _phase = _Phase.analyzing);
    try {
      final result = await _api.analyze(File(_path!));
      await AppStore.instance.addResult(result);
      setState(() {
        _result = result;
        _phase = _Phase.done;
      });
    } on ApiException catch (e) {
      setState(() => _phase = _Phase.recorded);
      _showError(e.message);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily voice check')),
      body: _phase == _Phase.done
          ? _ResultView(result: _result!)
          : _recordingView(context),
    );
  }

  Widget _recordingView(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Read the passage below aloud at a comfortable pace, '
                'in a quiet room.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    kReadingPassage,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _controls(context),
          ),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_phase) {
      case _Phase.idle:
        return Column(
          children: [
            FloatingActionButton.large(
              onPressed: _start,
              child: const Icon(Icons.mic),
            ),
            const SizedBox(height: 8),
            const Text('Tap to start recording'),
          ],
        );
      case _Phase.recording:
        return Column(
          children: [
            FloatingActionButton.large(
              onPressed: _stop,
              backgroundColor: scheme.errorContainer,
              child: const Icon(Icons.stop),
            ),
            const SizedBox(height: 8),
            Text('Recording…  ${_format(_elapsed)}'),
          ],
        );
      case _Phase.recorded:
        return Column(
          children: [
            FilledButton.icon(
              onPressed: _analyze,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Analyze recording'),
            ),
            TextButton(
              onPressed: _discard,
              child: const Text('Discard & re-record'),
            ),
          ],
        );
      case _Phase.analyzing:
        return const Column(
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('Uploading and analyzing… the first analysis of the day '
                'can take a minute.'),
          ],
        );
      case _Phase.done:
        return const SizedBox.shrink();
    }
  }

  static String _format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _ResultView extends StatelessWidget {
  final AnalysisResult result;

  const _ResultView({required this.result});

  static const _highlights = [
    MetricInfo('speech_rate_wpm', 'Speech rate', 'wpm', 0),
    MetricInfo('avg_pause_duration_s', 'Avg pause', 's', 2),
    MetricInfo('mean_pitch_hz', 'Pitch', 'Hz', 0),
    MetricInfo('mean_volume_db', 'Volume', 'dB', 1),
    MetricInfo('jitter_percent', 'Jitter', '%', 2),
    MetricInfo('hnr_db', 'Clarity (HNR)', 'dB', 1),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              ScoreRing(score: result.stabilityScore, size: 120),
              const SizedBox(height: 8),
              const Text('Speech stability'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(result.summary),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.4,
          children: [
            for (final metric in _highlights)
              if (result.metrics[metric.key] != null)
                _MetricTile(
                  label: metric.label,
                  value: metric.format(result.metrics[metric.key]!),
                ),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Transcript'),
          tilePadding: EdgeInsets.zero,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                result.transcript.isEmpty
                    ? 'No speech detected.'
                    : result.transcript,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
