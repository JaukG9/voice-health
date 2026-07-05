import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/analysis_result.dart';
import 'app_store.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Thin client for the local FastAPI backend.
class ApiService {
  Uri _uri(String path) {
    final base =
        AppStore.instance.serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  /// Uploads a recording and returns the full analysis.
  Future<AnalysisResult> analyze(File audio) async {
    final request = http.MultipartRequest('POST', _uri('/analyze'))
      ..fields['user_id'] = AppStore.instance.userId
      ..fields['recording_type'] = 'reading_passage'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));

    final http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(minutes: 5));
      response = await http.Response.fromStream(streamed);
    } on Exception {
      throw ApiException(
          'Could not reach the analysis server. Check that the backend is '
          'running and the server address in Settings is correct.');
    }
    if (response.statusCode != 200) {
      throw ApiException(_errorDetail(response));
    }
    return AnalysisResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<bool> ping() async {
    try {
      final response =
          await http.get(_uri('/health')).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort deletion of this user's history on the backend.
  Future<void> deleteServerHistory() async {
    try {
      await http
          .delete(_uri('/history/${AppStore.instance.userId}'))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  String _errorDetail(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['detail'].toString();
    } catch (_) {
      return 'Server error (${response.statusCode}).';
    }
  }
}
