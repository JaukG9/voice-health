import 'package:flutter_test/flutter_test.dart';
import 'package:voice_health/models/analysis_result.dart';

void main() {
  test('AnalysisResult round-trips through JSON', () {
    final result = AnalysisResult.fromJson({
      'id': 'abc123',
      'created_at': '2026-07-04T10:00:00+00:00',
      'recording_type': 'counting',
      'duration_s': 42.5,
      'transcript': 'When the sunlight strikes raindrops in the air',
      'confidence': 0.93,
      'metrics': {'speech_rate_wpm': 148.2, 'mean_pitch_hz': 121.0},
      'stability_score': 88,
      'summary': 'Your speech is very consistent with your personal baseline.',
      'trends': {
        'findings': ['Your average pitch is about 12% higher than your baseline.'],
      },
    });

    expect(result.metrics['speech_rate_wpm'], 148.2);
    expect(result.recordingType, 'counting');
    expect(result.stabilityScore, 88.0);
    expect(result.findings, hasLength(1));

    final restored = AnalysisResult.fromJson(result.toJson());
    expect(restored.id, result.id);
    expect(restored.createdAt, result.createdAt);
    expect(restored.recordingType, result.recordingType);
    expect(restored.metrics, result.metrics);
    expect(restored.summary, result.summary);
    expect(restored.findings, result.findings);
  });

  test('AnalysisResult tolerates missing fields', () {
    final result = AnalysisResult.fromJson(const {});
    expect(result.stabilityScore, isNull);
    expect(result.recordingType, 'reading_passage');
    expect(result.metrics, isEmpty);
    expect(result.findings, isEmpty);
  });
}
