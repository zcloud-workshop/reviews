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
  bool _isDisposed = false;

  QuestionBankController({QuestionBankRepository? repository})
      : _repository = repository ?? QuestionBankRepository();

  bool get isLoaded => _isLoaded;

  List<QuizModule> get modules => List.unmodifiable(_importedModules);

  List<QuizModule> get importedModules => List.unmodifiable(_importedModules);

  bool isImportedModule(String moduleId) =>
      _importedModules.any((module) => module.id == moduleId);

  Future<QuizModule?> deleteImportedModule(String moduleId) async {
    QuizModule? removed;
    await _persist((modules) {
      final index = modules.indexWhere((module) => module.id == moduleId);
      if (index < 0) return false;
      removed = modules.removeAt(index);
      return true;
    });
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
      if (!_isDisposed) notifyListeners();
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
    return _persist((modules) {
      final prepared = switch (strategy) {
        QuestionBankConflictStrategy.replaceImported =>
          _replaceImported(candidates, modules),
        QuestionBankConflictStrategy.keepBoth =>
          _renameConflicts(candidates, modules),
      };
      modules.addAll(prepared);
      return prepared.isNotEmpty;
    });
  }

  List<QuizModule> _replaceImported(
    List<QuizModule> candidates,
    List<QuizModule> modules,
  ) {
    final result = <QuizModule>[];
    final occupied = [...modules];

    for (final candidate in candidates) {
      final replaced = occupied
          .where(
            (module) =>
                module.id == candidate.id || module.name == candidate.name,
          )
          .toList(growable: false);
      modules.removeWhere(
        (module) => module.id == candidate.id || module.name == candidate.name,
      );
      occupied.removeWhere(
        (module) => module.id == candidate.id || module.name == candidate.name,
      );
      var module = candidate;
      if (replaced.isNotEmpty) {
        final refreshed = _withUniqueIdentity(
          candidate,
          [...occupied, ...replaced],
          idPrefix:
              '${candidate.id}-revision-${DateTime.now().microsecondsSinceEpoch}',
        );
        module = QuizModule(
          id: candidate.id,
          name: candidate.name,
          description: candidate.description,
          days: refreshed.days,
        );
      } else if (_hasAnyIdentityConflict(candidate, occupied)) {
        module = _withUniqueIdentity(candidate, occupied);
      }
      result.add(module);
      occupied.add(module);
    }
    return result;
  }

  List<QuizModule> _renameConflicts(
    List<QuizModule> candidates,
    List<QuizModule> modules,
  ) {
    final result = <QuizModule>[];
    final occupied = [...modules];
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
    List<QuizModule> existing, {
    String? idPrefix,
  }) {
    var sequence = 1;
    while (true) {
      final id = '${idPrefix ?? source.id}-import-$sequence';
      final name = '${source.name}（导入 $sequence）';
      final module = QuizModule(
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
                      id: '$id--${question.id}',
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
      if (!_hasAnyIdentityConflict(module, existing)) return module;
      sequence++;
    }
  }

  Future<void> _persist(bool Function(List<QuizModule>) update) {
    final operation = _writeQueue.then((_) async {
      await load();
      final snapshot = List<QuizModule>.from(_importedModules);
      if (!update(snapshot)) return;
      await _repository.saveImportedModules(snapshot);
      _importedModules
        ..clear()
        ..addAll(snapshot);
      if (!_isDisposed) notifyListeners();
    });
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
