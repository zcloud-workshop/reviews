import 'package:flutter/foundation.dart';

import '../models/quiz.dart';
import '../models/quiz_progress.dart';
import 'quiz_progress_repository.dart';

class QuizProgressController extends ChangeNotifier {
  final QuizProgressRepository _repository;

  final Map<String, QuizProgress> _progresses = {};
  Future<void>? _loadOperation;
  Future<void> _writeQueue = Future<void>.value();
  bool _isLoaded = false;

  QuizProgressController({QuizProgressRepository? repository})
      : _repository = repository ?? QuizProgressRepository();

  bool get isLoaded => _isLoaded;

  QuizProgress? progressFor(String dayId) => _progresses[dayId];

  QuizProgressStatus statusFor(String dayId) {
    return _progresses[dayId]?.status ?? QuizProgressStatus.notStarted;
  }

  int completedCount(Iterable<QuizDay> days) {
    return days
        .where((day) => statusFor(day.id) == QuizProgressStatus.completed)
        .length;
  }

  Future<void> load() {
    return _loadOperation ??= _load();
  }

  Future<void> _load() async {
    try {
      _progresses
        ..clear()
        ..addAll(await _repository.loadAll());
    } catch (_) {
      _progresses.clear();
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> saveDraft(
    String dayId,
    Map<String, dynamic> answers,
  ) {
    final previous = _progresses[dayId];
    _progresses[dayId] = QuizProgress(
      dayId: dayId,
      answers: _copyAnswers(answers),
      submitted: false,
      lastAccuracy: previous?.lastAccuracy,
      updatedAt: DateTime.now(),
      completedAt: previous?.completedAt,
    );
    notifyListeners();
    return _persist();
  }

  Future<void> complete(
    String dayId,
    Map<String, dynamic> answers, {
    required double accuracy,
  }) {
    final now = DateTime.now();
    _progresses[dayId] = QuizProgress(
      dayId: dayId,
      answers: _copyAnswers(answers),
      submitted: true,
      lastAccuracy: accuracy,
      updatedAt: now,
      completedAt: now,
    );
    notifyListeners();
    return _persist();
  }

  Future<void> clearForModule(QuizModule module) {
    final dayIds = module.days.map((day) => day.id).toSet();
    final before = _progresses.length;
    _progresses.removeWhere((dayId, _) => dayIds.contains(dayId));
    if (_progresses.length == before) return flush();
    notifyListeners();
    return _persist();
  }

  Future<void> flush() => _writeQueue;

  Future<void> _persist() {
    final snapshot = Map<String, QuizProgress>.from(_progresses);
    _writeQueue = _writeQueue
        .then((_) => _repository.saveAll(snapshot))
        .catchError((Object _) {
      // 保留内存状态；后续写入仍可继续，不因一次失败打断队列。
    });
    return _writeQueue;
  }

  Map<String, dynamic> _copyAnswers(Map<String, dynamic> answers) {
    return answers.map((questionId, answer) {
      final copiedAnswer = answer is List ? List<dynamic>.from(answer) : answer;
      return MapEntry(questionId, copiedAnswer);
    });
  }
}
