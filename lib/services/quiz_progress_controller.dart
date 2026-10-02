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
  bool _isDisposed = false;

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
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> saveDraft(
    String dayId,
    Map<String, dynamic> answers,
  ) {
    final copiedAnswers = _copyAnswers(answers);
    return _persist((progresses) {
      final previous = progresses[dayId];
      progresses[dayId] = QuizProgress(
        dayId: dayId,
        answers: copiedAnswers,
        submitted: false,
        lastAccuracy: previous?.lastAccuracy,
        updatedAt: DateTime.now(),
        completedAt: previous?.completedAt,
      );
      return true;
    });
  }

  Future<void> complete(
    String dayId,
    Map<String, dynamic> answers, {
    required double accuracy,
  }) {
    final now = DateTime.now();
    final copiedAnswers = _copyAnswers(answers);
    return _persist((progresses) {
      progresses[dayId] = QuizProgress(
        dayId: dayId,
        answers: copiedAnswers,
        submitted: true,
        lastAccuracy: accuracy,
        updatedAt: now,
        completedAt: now,
      );
      return true;
    });
  }

  Future<void> clearForModule(QuizModule module) {
    final dayIds = module.days.map((day) => day.id).toSet();
    return _persist((progresses) {
      final before = progresses.length;
      progresses.removeWhere((dayId, _) => dayIds.contains(dayId));
      return progresses.length != before;
    });
  }

  Future<void> flush() => _writeQueue;

  Future<void> _persist(bool Function(Map<String, QuizProgress>) update) {
    final operation = _writeQueue.then((_) async {
      await load();
      final snapshot = Map<String, QuizProgress>.from(_progresses);
      if (!update(snapshot)) return;
      await _repository.saveAll(snapshot);
      _progresses
        ..clear()
        ..addAll(snapshot);
      if (!_isDisposed) notifyListeners();
    });
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  Map<String, dynamic> _copyAnswers(Map<String, dynamic> answers) {
    return answers.map((questionId, answer) {
      final copiedAnswer = answer is List ? List<dynamic>.from(answer) : answer;
      return MapEntry(questionId, copiedAnswer);
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
