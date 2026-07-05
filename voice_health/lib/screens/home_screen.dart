import 'package:flutter/material.dart';

import '../models/check_type.dart';
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
              _TodayCard(
                doneCount: kCheckTypes
                    .where((t) => store.recordedTodayType(t.key))
                    .length,
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
                children: [
                  for (final type in kCheckTypes)
                    _CheckTile(
                      type: type,
                      done: store.recordedTodayType(type.key),
                    ),
                ],
              ),
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
  final int doneCount;

  const _TodayCard({required this.doneCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allDone = doneCount == kCheckTypes.length;
    final message = allDone
        ? 'All voice checks done today. Nice work!'
        : doneCount == 0
            ? "You haven't recorded today yet — pick a check below."
            : '$doneCount of ${kCheckTypes.length} voice checks done today.';
    return Card(
      elevation: 0,
      color: allDone ? scheme.primaryContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              allDone ? Icons.check_circle : Icons.mic_none,
              size: 36,
              color: scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final CheckType type;
  final bool done;

  const _CheckTile({required this.type, required this.done});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RecordScreen(type: type)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(type.icon, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      type.tagline,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (done)
                Icon(Icons.check_circle,
                    size: 18, color: scheme.primary),
            ],
          ),
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
