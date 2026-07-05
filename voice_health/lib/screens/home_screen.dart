import 'package:flutter/material.dart';

import '../services/app_store.dart';
import '../widgets/score_ring.dart';
import '../widgets/stat_card.dart';
import 'record_screen.dart';

/// Dashboard: today's status, streak, stability score and the latest summary.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final store = AppStore.instance;
        return Scaffold(
          appBar: AppBar(title: const Text('NeuroVoice AI')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _greeting(store.displayName),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _TodayCard(recordedToday: store.recordedToday),
              const SizedBox(height: 12),
              Row(
                children: [
                  StatCard(
                    value: '${store.recordingCount}',
                    label: 'Recordings',
                    icon: Icons.mic,
                  ),
                  const SizedBox(width: 8),
                  StatCard(
                    value: '${store.streak}',
                    label: 'Day streak',
                    icon: Icons.local_fire_department,
                  ),
                  const SizedBox(width: 8),
                  StatCard(
                    value: '${store.daysTracked}',
                    label: 'Days tracked',
                    icon: Icons.calendar_today,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StabilityCard(score: store.latest?.stabilityScore),
              const SizedBox(height: 12),
              if (store.latest != null) _SummaryCard(text: store.latest!.summary),
              const SizedBox(height: 20),
              Text(
                'NeuroVoice AI tracks changes against your own voice over time. '
                'It does not diagnose any condition.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  String _greeting(String name) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    return name.isEmpty ? part : '$part, $name';
  }
}

class _TodayCard extends StatelessWidget {
  final bool recordedToday;

  const _TodayCard({required this.recordedToday});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: recordedToday ? scheme.primaryContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              recordedToday ? Icons.check_circle : Icons.mic_none,
              size: 36,
              color: scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                recordedToday
                    ? "Today's voice check is done. Nice work!"
                    : "You haven't recorded today yet.",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecordScreen()),
              ),
              icon: const Icon(Icons.mic),
              label: Text(recordedToday ? 'Again' : 'Record'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StabilityCard extends StatelessWidget {
  final double? score;

  const _StabilityCard({required this.score});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ScoreRing(score: score),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Speech stability',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    score == null
                        ? 'Available after a few recordings — your first '
                            'samples become your personal baseline.'
                        : 'How consistent your latest recording is with '
                            'your personal baseline (100 = unchanged).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String text;

  const _SummaryCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Latest summary',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
