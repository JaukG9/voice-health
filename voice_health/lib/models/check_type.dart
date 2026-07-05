import 'package:flutter/material.dart';

/// One kind of daily voice check. The key matches the backend's
/// `recording_type`, and baselines/trends are tracked per type.
class CheckType {
  final String key;
  final String title;
  final String shortTitle;
  final String tagline;
  final IconData icon;
  final String instructions;
  final String content;

  const CheckType({
    required this.key,
    required this.title,
    required this.shortTitle,
    required this.tagline,
    required this.icon,
    required this.instructions,
    required this.content,
  });

  /// What to show in the prompt card. Free speech rotates through prompts
  /// daily so there's always something to talk about.
  String get displayContent {
    if (key != 'free_speech') return content;
    final day = DateTime.now().difference(DateTime(2026)).inDays;
    return _freeSpeechPrompts[day % _freeSpeechPrompts.length];
  }
}

const kReadingPassage = CheckType(
  key: 'reading_passage',
  title: 'Reading passage',
  shortTitle: 'Reading',
  tagline: 'Read a short paragraph',
  icon: Icons.menu_book,
  instructions:
      'Read the passage below aloud at a comfortable pace, in a quiet room.',
  // The Rainbow Passage — a standard text used in speech assessment, so every
  // recording is directly comparable to the previous ones.
  content:
      'When the sunlight strikes raindrops in the air, they act as a prism '
      'and form a rainbow. The rainbow is a division of white light into many '
      'beautiful colors. These take the shape of a long round arch, with its '
      'path high above, and its two ends apparently beyond the horizon. There '
      'is, according to legend, a boiling pot of gold at one end. People '
      'look, but no one ever finds it. When a man looks for something beyond '
      'his reach, his friends say he is looking for the pot of gold at the '
      'end of the rainbow.',
);

const kSustainedVowel = CheckType(
  key: 'sustained_vowel',
  title: 'Sustained "Ahh"',
  shortTitle: '"Ahh"',
  tagline: 'Hold a steady note',
  icon: Icons.graphic_eq,
  instructions:
      'Take a deep breath, then hold a steady "Ahhhh" at a comfortable pitch '
      'and loudness for about 10 seconds — all in one breath. This measures '
      'vocal stability, tremor and breath support.',
  content: 'Ahhhhhh…',
);

const kCounting = CheckType(
  key: 'counting',
  title: 'Counting',
  shortTitle: 'Counting',
  tagline: 'Count from 1 to 20',
  icon: Icons.format_list_numbered,
  instructions:
      'Count out loud from 1 to 20 at your natural pace. This measures '
      'pacing, pauses and articulation.',
  content: '1   2   3   4   5   6   7   8   9   10\n'
      '11   12   13   14   15   16   17   18   19   20',
);

const kFreeSpeech = CheckType(
  key: 'free_speech',
  title: 'Free speech',
  shortTitle: 'Free speech',
  tagline: 'Talk about the daily prompt',
  icon: Icons.chat_bubble_outline,
  instructions:
      'Speak freely for 30–60 seconds about the prompt below. There are no '
      'wrong answers — this measures your spontaneous, everyday speech.',
  content: '', // rotates daily, see displayContent
);

const _freeSpeechPrompts = [
  'Describe your day so far — what have you done since you woke up?',
  'Describe the room you are in right now, in as much detail as you can.',
  'How are you feeling today, physically and emotionally?',
  'Describe your favorite meal and how it is prepared.',
  'Talk about a place you would like to visit, and why.',
  'Describe what you can see out of the nearest window.',
  'Talk about a hobby or activity you enjoy.',
];

const kCheckTypes = [kReadingPassage, kSustainedVowel, kCounting, kFreeSpeech];

CheckType checkTypeByKey(String key) =>
    kCheckTypes.firstWhere((t) => t.key == key, orElse: () => kReadingPassage);
