import 'package:flutter/material.dart';

/// Color band for a 0-100 stability score.
Color scoreColor(BuildContext context, double? score) {
  if (score == null) return Theme.of(context).colorScheme.outline;
  if (score >= 85) return const Color(0xFF2E7D32);
  if (score >= 70) return const Color(0xFF827717);
  if (score >= 50) return const Color(0xFFEF6C00);
  return const Color(0xFFC62828);
}

/// Circular gauge showing the overall speech stability score.
class ScoreRing extends StatelessWidget {
  final double? score;
  final double size;

  const ScoreRing({super.key, required this.score, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final color = scoreColor(context, score);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score == null ? 0 : score! / 100,
            strokeWidth: size / 12,
            strokeCap: StrokeCap.round,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
          Center(
            child: Text(
              score == null ? '—' : score!.round().toString(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
