import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/quiz_progress.dart';

class QuizProgressRepository {
  static const _storageKey = 'quiz_progress_v1';

  SharedPreferences? _preferences;

  QuizProgressRepository({SharedPreferences? preferences})
      : _preferences = preferences;

  Future<Map<String, QuizProgress>> loadAll() async {
    final preferences = await _getPreferences();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return <String, QuizProgress>{};
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map || decoded['days'] is! Map) {
        return <String, QuizProgress>{};
      }

      final progresses = <String, QuizProgress>{};
      for (final entry in (decoded['days'] as Map).entries) {
        if (entry.value is! Map) {
          continue;
        }
        final progress = QuizProgress.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        final dayId =
            progress.dayId.isEmpty ? entry.key.toString() : progress.dayId;
        if (dayId.isNotEmpty) {
          progresses[dayId] = QuizProgress(
            dayId: dayId,
            answers: progress.answers,
            submitted: progress.submitted,
            lastAccuracy: progress.lastAccuracy,
            updatedAt: progress.updatedAt,
            completedAt: progress.completedAt,
          );
        }
      }
      return progresses;
    } on FormatException {
      return <String, QuizProgress>{};
    }
  }

  Future<void> saveAll(Map<String, QuizProgress> progresses) async {
    final preferences = await _getPreferences();
    final encoded = jsonEncode({
      'version': 1,
      'days': progresses.map(
        (dayId, progress) => MapEntry(dayId, progress.toJson()),
      ),
    });
    if (!await preferences.setString(_storageKey, encoded)) {
      throw StateError('学习进度保存失败');
    }
  }

  Future<SharedPreferences> _getPreferences() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }
}
