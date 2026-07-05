import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_result.dart';

/// Single source of truth for profile settings and analysis history.
///
/// History lives in a JSON file in the app documents directory. Nothing
/// leaves the device except the audio sent to your own backend for analysis.
class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore instance = AppStore._();

  late SharedPreferences _prefs;
  late File _historyFile;
  List<AnalysisResult> history = [];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    if (_prefs.getString('userId') == null) {
      final random = Random.secure();
      final id =
          List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
      await _prefs.setString('userId', id);
    }
    final dir = await getApplicationDocumentsDirectory();
    _historyFile = File('${dir.path}/history.json');
    if (await _historyFile.exists()) {
      try {
        final list = jsonDecode(await _historyFile.readAsString()) as List;
        history = list
            .map((e) => AnalysisResult.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        history = [];
      }
    }
  }

  // ---- Profile & settings ----

  String get userId => _prefs.getString('userId')!;

  String get displayName => _prefs.getString('displayName') ?? '';
  Future<void> setDisplayName(String value) async {
    await _prefs.setString('displayName', value.trim());
    notifyListeners();
  }

  /// Address of the FastAPI backend. `10.0.2.2` reaches the host machine
  /// from the Android emulator; use your PC's LAN IP on a physical phone.
  String get serverUrl =>
      _prefs.getString('serverUrl') ?? 'http://10.0.2.2:8000';
  Future<void> setServerUrl(String value) async {
    await _prefs.setString('serverUrl', value.trim());
    notifyListeners();
  }

  // ---- History ----

  Future<void> addResult(AnalysisResult result) async {
    history.add(result);
    history.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await _save();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history = [];
    await _save();
    notifyListeners();
  }

  Future<void> _save() => _historyFile
      .writeAsString(jsonEncode(history.map((r) => r.toJson()).toList()));

  // ---- Derived dashboard stats ----

  AnalysisResult? get latest => history.isEmpty ? null : history.last;

  int get recordingCount => history.length;

  int get daysTracked => history.isEmpty
      ? 0
      : DateTime.now().difference(history.first.createdAt).inDays + 1;

  bool get recordedToday =>
      history.any((r) => _isSameDay(r.createdAt, DateTime.now()));

  /// Consecutive days with at least one recording. Today counts if recorded;
  /// otherwise the streak ending yesterday is still shown.
  int get streak {
    final days = history
        .map((r) =>
            DateTime(r.createdAt.year, r.createdAt.month, r.createdAt.day))
        .toSet();
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (!days.contains(day)) day = day.subtract(const Duration(days: 1));
    var count = 0;
    while (days.contains(day)) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
