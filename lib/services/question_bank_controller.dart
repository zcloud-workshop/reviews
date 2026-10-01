import 'package:flutter/foundation.dart';

import '../models/quiz.dart';
import 'question_bank_repository.dart';

enum QuestionBankConflictStrategy {
  replaceImported,
  keepBoth,
}

class QuestionBankController extends ChangeNotifier {
  final QuestionBankRepository _repository;

  final List<QuizModule> _importedModules = [];
  Future<void>? _loadOperation;
  Future<void> _writeQueue = Future<void>.value();
  bool _isLoaded = false;

  QuestionBankController({QuestionBankRepository? repository})
      : _repository = repository ?? QuestionBankRepository();

  bool get isLoaded => _isLoaded;

  List<QuizModule> get modules => List.unmodifiable(_importedModules);

  List<QuizModule> get importedModules => List.unmodifiable(_importedModules);

  bool isImportedModule(String moduleId) =>
      _importedModules.any((module) => module.id == moduleId);

  Future<QuizModule?> deleteImportedModule(String moduleId) async {
    final index =
        _importedModules.indexWhere((module) => module.id == moduleId);
    if (index < 0) return null;
    final removed = _importedModules.removeAt(index);
    notifyListeners();
    await _persist();
    return removed;
  }

  Future<void> load() => _loadOperation ??= _load();

  Future<void> _load() async {
    try {
      _importedModules
        ..clear()
        ..addAll(await _repository.loadImportedModules());
    } catch (_) {
      _importedModules.clear();
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  List<QuizModule> conflictingModules(Iterable<QuizModule> candidates) {
    final existing = modules;
    return candidates
        .where(
          (candidate) => existing.any(
            (module) =>
                module.id == candidate.id || module.name == candidate.name,
          ),
        )
        .toList(growable: false);
  }

  Future<void> importModules(
    List<QuizModule> candidates, {
    required QuestionBankConflictStrategy strategy,
  }) {
    final prepared = switch (strategy) {
      QuestionBankConflictStrategy.replaceImported =>
        _replaceImported(candidates),
      QuestionBankConflictStrategy.keepBoth => _renameConflicts(candidates),
    };
    _importedModules.addAll(prepared);
    notifyListeners();
    return _persist();
  }

  List<QuizModule> _replaceImported(List<QuizModule> candidates) {
    final result = <QuizModule>[];
    final occupied = [..._importedModules];

    for (final candidate in candidates) {
      _importedModules.removeWhere(
        (module) => module.id == candidate.id || module.name == candidate.name,
      );
      occupied.removeWhere(
        (module) => module.id == candidate.id || module.name == candidate.name,
      );
      final module = _hasAnyIdentityConflict(candidate, occupied)
          ? _withUniqueIdentity(candidate, occupied)
          : candidate;
      result.add(module);
      occupied.add(module);
    }
    return result;
  }

  List<QuizModule> _renameConflicts(List<QuizModule> candidates) {
    final result = <QuizModule>[];
    final occupied = modules.toList(growable: true);
    for (final candidate in candidates) {
      final module = _hasAnyIdentityConflict(candidate, occupied)
          ? _withUniqueIdentity(candidate, occupied)
          : candidate;
      result.add(module);
      occupied.add(module);
    }
    return result;
  }

  bool _hasAnyIdentityConflict(
    QuizModule candidate,
    List<QuizModule> existing,
  ) {
    final existingModuleIds = existing.map((module) => module.id).toSet();
    final existingModuleNames = existing.map((module) => module.name).toSet();
    final existingDayIds =
        existing.expand((module) => module.days).map((day) => day.id).toSet();
    final existingQuestionIds = existing
        .expand((module) => module.days)
        .expand((day) => day.questions)
        .map((question) => question.id)
        .toSet();

    return existingModuleIds.contains(candidate.id) ||
        existingModuleNames.contains(candidate.name) ||
        candidate.days.any(
          (day) =>
              existingDayIds.contains(day.id) ||
              day.questions.any(
                (question) => existingQuestionIds.contains(question.id),
              ),
        );
  }

  QuizModule _withUniqueIdentity(
    QuizModule source,
    List<QuizModule> existing,
  ) {
    final usedIds = existing.map((module) => module.id).toSet();
    final usedNames = existing.map((module) => module.name).toSet();
    var sequence = 1;
    var id = '${source.id}-import-$sequence';
    var name = '${source.name}（导入 $sequence）';
    while (usedIds.contains(id) || usedNames.contains(name)) {
      sequence++;
      id = '${source.id}-import-$sequence';
      name = '${source.name}（导入 $sequence）';
    }

    return QuizModule(
      id: id,
      name: name,
      description: source.description,
      days: source.days.map(
        (day) {
          final dayId = '$id--${day.id}';
          return QuizDay(
            id: dayId,
            title: day.title,
            questions: day.questions
                .map(
                  (question) => Question(
                    id: '$dayId--${question.id}',
                    type: question.type,
                    content: question.content,
                    options: question.options,
                    answer: question.answer,
                  ),
                )
                .toList(growable: false),
          );
        },
      ).toList(growable: false),
    );
  }

  Future<void> _persist() {
    final snapshot = List<QuizModule>.from(_importedModules);
    _writeQueue = _writeQueue
        .then((_) => _repository.saveImportedModules(snapshot))
        .catchError((Object _) {});
    return _writeQueue;
  }
}
