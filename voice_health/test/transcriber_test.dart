import 'package:flutter_test/flutter_test.dart';
import 'package:voice_health/analysis/transcriber.dart';

void main() {
  test('single-word segment passes through unchanged', () {
    final words = wordsFromSegment(' rainbow ', 1.0, 1.4);
    expect(words, hasLength(1));
    expect(words.single.word, 'rainbow');
    expect(words.single.start, 1.0);
    expect(words.single.end, 1.4);
  });

  test('multi-word segment is split proportionally to word length', () {
    final words = wordsFromSegment('the sunlight', 0.0, 1.2);
    expect(words, hasLength(2));
    expect(words[0].word, 'the');
    expect(words[1].word, 'sunlight');
    // 'the' = 3 of 11 chars -> 3/11 of the 1.2 s interval.
    expect(words[0].end, closeTo(1.2 * 3 / 11, 1e-9));
    expect(words[1].start, words[0].end);
    expect(words[1].end, closeTo(1.2, 1e-9));
  });

  test('non-speech markers are dropped', () {
    expect(wordsFromSegment('[BLANK_AUDIO]', 0, 1), isEmpty);
    expect(wordsFromSegment('(silence)', 0, 1), isEmpty);
    expect(wordsFromSegment('   ', 0, 1), isEmpty);
  });
}
