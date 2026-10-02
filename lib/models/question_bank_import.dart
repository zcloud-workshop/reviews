import 'quiz.dart';

class QuestionBankImportPreview {
  final List<QuizModule> modules;
  final int dayCount;
  final int questionCount;

  const QuestionBankImportPreview({
    required this.modules,
    required this.dayCount,
    required this.questionCount,
  });
}

class QuestionBankImportException implements Exception {
  final List<String> errors;

  const QuestionBankImportException(this.errors);

  @override
  String toString() => errors.join('\n');
}
