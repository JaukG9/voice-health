import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../analysis/local_analyzer.dart';
import '../models/analysis_result.dart';
import '../models/check_type.dart';
import '../services/api_service.dart';
import '../services/app_store.dart';
import '../services/recorder_service.dart';
import '../widgets/score_ring.dart';

enum _Phase { idle, recording, recorded, analyzing, done }

/// Daily voice check: complete the given task aloud, then send it for
/// analysis. Each check type keeps its own baseline and trends.
class RecordScreen extends StatefulWidget {
  final CheckType type;

  const RecordScreen({super.key, this.type = kReadingPassage});

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
  String _analyzingStatus = '';

  bool get _isVowel => widget.type.key == 'sustained_vowel';

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
    final onDevice = AppStore.instance.analysisMode == 'device';
    setState(() {
      _phase = _Phase.analyzing;
      _analyzingStatus = onDevice
          ? 'Analyzing on this phone…'
          : 'Uploading and analyzing… the first analysis of the day '
              'can take a minute.';
    });
    try {
      final AnalysisResult result;
      if (onDevice) {
        result = await LocalAnalyzer().analyze(
          File(_path!),
          widget.type,
          onStatus: (status) {
            if (mounted) setState(() => _analyzingStatus = status);
          },
        );
      } else {
        result = await _api.analyze(File(_path!), widget.type.key);
      }
      await AppStore.instance.addResult(result);
      setState(() {
        _result = result;
        _phase = _Phase.done;
      });
    } on ApiException catch (e) {
      setState(() => _phase = _Phase.recorded);
      _showError(e.message);
    } on LocalAnalysisException catch (e) {
      setState(() => _phase = _Phase.recorded);
      _showError(e.message);
    } catch (e) {
      // Never leave the user staring at a frozen progress bar.
      setState(() => _phase = _Phase.recorded);
      _showError('Analysis failed unexpectedly: $e');
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
      appBar: AppBar(title: Text(widget.type.title)),
      body: _phase == _Phase.done
          ? _ResultView(result: _result!, type: widget.type)
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
                widget.type.instructions,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.type.displayContent,
                    textAlign: _isVowel ? TextAlign.center : TextAlign.start,
                    style: _isVowel
                        ? Theme.of(context).textTheme.headlineMedium
                        : Theme.of(context)
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
            Text(_isVowel
                ? 'Recording…  ${_format(_elapsed)} — aim for about 10 seconds'
                : 'Recording…  ${_format(_elapsed)}'),
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
        return Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(_analyzingStatus, textAlign: TextAlign.center),
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
  final CheckType type;

  const _ResultView({required this.result, required this.type});

  static const _speechHighlights = [
    MetricInfo('speech_rate_wpm', 'Speech rate', 'wpm', 0),
    MetricInfo('avg_pause_duration_s', 'Avg pause', 's', 2),
    MetricInfo('mean_pitch_hz', 'Pitch', 'Hz', 0),
    MetricInfo('mean_volume_db', 'Volume', 'dB', 1),
    MetricInfo('jitter_percent', 'Jitter', '%', 2),
    MetricInfo('hnr_db', 'Clarity (HNR)', 'dB', 1),
  ];

  static const _vowelHighlights = [
    MetricInfo('duration_s', 'Phonation', 's', 1),
    MetricInfo('mean_pitch_hz', 'Pitch', 'Hz', 0),
    MetricInfo('pitch_variability_semitones', 'Pitch variation', 'st', 1),
    MetricInfo('jitter_percent', 'Jitter', '%', 2),
    MetricInfo('shimmer_percent', 'Shimmer', '%', 2),
    MetricInfo('hnr_db', 'Clarity (HNR)', 'dB', 1),
  ];

  @override
  Widget build(BuildContext context) {
    final isVowel = type.key == 'sustained_vowel';
    final highlights = isVowel ? _vowelHighlights : _speechHighlights;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              ScoreRing(score: result.stabilityScore, size: 120),
              const SizedBox(height: 8),
              Text(isVowel ? 'Voice stability' : 'Speech stability'),
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
            for (final metric in highlights)
              if (result.metrics[metric.key] != null)
                _MetricTile(
                  label: metric.label,
                  value: metric.format(result.metrics[metric.key]!),
                ),
          ],
        ),
        if (!isVowel) ...[
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
        ],
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
