import 'dart:convert';

import '../models/question_bank_import.dart';
import '../models/quiz.dart';

class QuestionBankCodec {
  static const formatVersion = 1;

  const QuestionBankCodec._();

  static QuestionBankImportPreview decode(String source) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const QuestionBankImportException(['文件不是有效的 JSON 格式。']);
    }

    if (decoded is! Map) {
      throw const QuestionBankImportException(['题库根节点必须是 JSON 对象。']);
    }

    final root = Map<String, dynamic>.from(decoded);
    final errors = <String>[];
    final version = root['formatVersion'];
    if (version != formatVersion) {
      errors.add('仅支持 formatVersion: $formatVersion 的题库文件。');
    }

    final rawModules = root['modules'];
    if (rawModules is! List || rawModules.isEmpty) {
      errors.add('modules 必须是至少包含一个模块的数组。');
    }

    if (errors.isNotEmpty) {
      throw QuestionBankImportException(errors);
    }

    final moduleIds = <String>{};
    final moduleNames = <String>{};
    final dayIds = <String>{};
    final questionIds = <String>{};
    final modules = <QuizModule>[];

    for (var moduleIndex = 0; moduleIndex < rawModules.length; moduleIndex++) {
      final module = _parseModule(
        rawModules[moduleIndex],
        moduleIndex: moduleIndex,
        moduleIds: moduleIds,
        moduleNames: moduleNames,
        dayIds: dayIds,
        questionIds: questionIds,
        errors: errors,
      );
      if (module != null) {
        modules.add(module);
      }
    }

    if (errors.isNotEmpty) {
      throw QuestionBankImportException(errors);
    }

    final dayCount = modules.fold<int>(
      0,
      (total, module) => total + module.days.length,
    );
    final questionCount = modules.fold<int>(
      0,
      (total, module) =>
          total +
          module.days.fold<int>(
            0,
            (dayTotal, day) => dayTotal + day.questions.length,
          ),
    );

    return QuestionBankImportPreview(
      modules: modules,
      dayCount: dayCount,
      questionCount: questionCount,
    );
  }

  static QuizModule? _parseModule(
    dynamic rawModule, {
    required int moduleIndex,
    required Set<String> moduleIds,
    required Set<String> moduleNames,
    required Set<String> dayIds,
    required Set<String> questionIds,
    required List<String> errors,
  }) {
    final path = '模块 ${moduleIndex + 1}';
    if (rawModule is! Map) {
      errors.add('$path 必须是对象。');
      return null;
    }
    final module = Map<String, dynamic>.from(rawModule);
    final id = _requiredText(module['id'], '$path.id', errors);
    final name = _requiredText(module['name'], '$path.name', errors);
    final rawDays = module['days'];

    if (id != null && !moduleIds.add(id)) {
      errors.add('$path.id “$id” 重复。');
    }
    if (name != null && !moduleNames.add(name)) {
      errors.add('$path.name “$name” 重复。');
    }
    if (rawDays is! List || rawDays.isEmpty) {
      errors.add('$path.days 必须是至少包含一个练习组的数组。');
    }

    final days = <QuizDay>[];
    if (rawDays is List) {
      for (var dayIndex = 0; dayIndex < rawDays.length; dayIndex++) {
        final day = _parseDay(
          rawDays[dayIndex],
          path: '$path / 练习组 ${dayIndex + 1}',
          dayIds: dayIds,
          questionIds: questionIds,
          errors: errors,
        );
        if (day != null) {
          days.add(day);
        }
      }
    }

    if (id == null || name == null || days.isEmpty) {
      return null;
    }
    return QuizModule(
      id: id,
      name: name,
      description: _optionalText(module['description']) ?? '',
      days: days,
    );
  }

  static QuizDay? _parseDay(
    dynamic rawDay, {
    required String path,
    required Set<String> dayIds,
    required Set<String> questionIds,
    required List<String> errors,
  }) {
    if (rawDay is! Map) {
      errors.add('$path 必须是对象。');
      return null;
    }
    final day = Map<String, dynamic>.from(rawDay);
    final id = _requiredText(day['id'], '$path.id', errors);
    final title = _requiredText(day['title'], '$path.title', errors);
    final rawQuestions = day['questions'];

    if (id != null && !dayIds.add(id)) {
      errors.add('$path.id “$id” 在题库中重复。');
    }
    if (rawQuestions is! List || rawQuestions.isEmpty) {
      errors.add('$path.questions 必须是至少包含一道题的数组。');
    }

    final questions = <Question>[];
    if (rawQuestions is List) {
      for (var questionIndex = 0;
          questionIndex < rawQuestions.length;
          questionIndex++) {
        final question = _parseQuestion(
          rawQuestions[questionIndex],
          path: '$path / 第 ${questionIndex + 1} 题',
          questionIds: questionIds,
          errors: errors,
        );
        if (question != null) {
          questions.add(question);
        }
      }
    }

    if (id == null || title == null || questions.isEmpty) {
      return null;
    }
    return QuizDay(id: id, title: title, questions: questions);
  }

  static Question? _parseQuestion(
    dynamic rawQuestion, {
    required String path,
    required Set<String> questionIds,
    required List<String> errors,
  }) {
    if (rawQuestion is! Map) {
      errors.add('$path 必须是对象。');
      return null;
    }
    final question = Map<String, dynamic>.from(rawQuestion);
    final id = _requiredText(question['id'], '$path.id', errors);
    final content = _requiredText(question['content'], '$path.content', errors);
    final type = _parseType(question['type'], '$path.type', errors);

    if (id != null && !questionIds.add(id)) {
      errors.add('$path.id “$id” 在题库中重复。');
    }
    if (type == null) {
      return null;
    }

    final options = _parseOptions(question['options'], path, type, errors);
    final answer =
        _parseAnswer(question['answer'], path, type, options, errors);

    if (id == null || content == null || answer == null) {
      return null;
    }
    return Question(
      id: id,
      type: type,
      content: content,
      options: options,
      answer: answer,
    );
  }

  static QuestionType? _parseType(
    dynamic value,
    String path,
    List<String> errors,
  ) {
    final type = switch (value) {
      'choice' => QuestionType.choice,
      'multi' => QuestionType.multi,
      'judge' => QuestionType.judge,
      'fill' => QuestionType.fill,
      'shortAnswer' => QuestionType.shortAnswer,
      _ => null,
    };
    if (type == null) {
      errors.add('$path 必须为 choice、multi、judge、fill 或 shortAnswer。');
    }
    return type;
  }

  static List<String> _parseOptions(
    dynamic value,
    String path,
    QuestionType type,
    List<String> errors,
  ) {
    final requiresOptions =
        type == QuestionType.choice || type == QuestionType.multi;
    if (value == null && !requiresOptions) {
      return const <String>[];
    }
    if (value is! List) {
      errors.add('$path.options 必须是字符串数组。');
      return const <String>[];
    }
    final options = <String>[];
    for (var index = 0; index < value.length; index++) {
      final option = _requiredText(
        value[index],
        '$path.options[${index + 1}]',
        errors,
      );
      if (option != null) {
        options.add(option);
      }
    }
    if (requiresOptions && options.length < 2) {
      errors.add('$path 的单选题或多选题至少需要 2 个选项。');
    }
    return options;
  }

  static dynamic _parseAnswer(
    dynamic value,
    String path,
    QuestionType type,
    List<String> options,
    List<String> errors,
  ) {
    switch (type) {
      case QuestionType.choice:
        if (value is! int || value < 0 || value >= options.length) {
          errors.add('$path.answer 必须是有效的选项序号（从 0 开始）。');
          return null;
        }
        return value;
      case QuestionType.multi:
        if (value is! List || value.isEmpty) {
          errors.add('$path.answer 必须是至少包含一个选项序号的数组。');
          return null;
        }
        final answers = <int>[];
        for (final answer in value) {
          if (answer is! int || answer < 0 || answer >= options.length) {
            errors.add('$path.answer 含有无效的选项序号。');
            return null;
          }
          answers.add(answer);
        }
        if (answers.toSet().length != answers.length) {
          errors.add('$path.answer 不能包含重复的选项序号。');
          return null;
        }
        return answers;
      case QuestionType.judge:
        if (value is! bool) {
          errors.add('$path.answer 必须为 true 或 false。');
          return null;
        }
        return value;
      case QuestionType.fill:
        if (value is! List || value.isEmpty) {
          errors.add('$path.answer 必须是至少包含一个标准答案的数组。');
          return null;
        }
        final answers = <String>[];
        for (var index = 0; index < value.length; index++) {
          final answer = _requiredText(
            value[index],
            '$path.answer[${index + 1}]',
            errors,
          );
          if (answer != null) {
            answers.add(answer);
          }
        }
        return answers.length == value.length ? answers : null;
      case QuestionType.shortAnswer:
        return _requiredText(value, '$path.answer', errors);
    }
  }

  static String? _requiredText(
    dynamic value,
    String path,
    List<String> errors,
  ) {
    final text = _optionalText(value);
    if (text == null) {
      errors.add('$path 必须是非空字符串。');
    }
    return text;
  }

  static String? _optionalText(dynamic value) {
    if (value is! String) {
      return null;
    }
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
