import '../models/quiz.dart';

enum AnswerStatus {
  correct,
  incorrect,
  unanswered,
  pendingReview,
}

class QuizResult {
  final int total;
  final int correct;
  final int incorrect;
  final int unanswered;
  final int pendingReview;
  final int autoGradableTotal;

  const QuizResult({
    required this.total,
    required this.correct,
    required this.incorrect,
    required this.unanswered,
    required this.pendingReview,
    required this.autoGradableTotal,
  });

  double get accuracy =>
      autoGradableTotal == 0 ? 0 : correct / autoGradableTotal;
}

class AnswerEvaluator {
  const AnswerEvaluator._();

  static bool isAnswered(Question question, dynamic userAnswer) {
    switch (question.type) {
      case QuestionType.choice:
        return userAnswer is int;
      case QuestionType.multi:
        return userAnswer is Iterable && userAnswer.isNotEmpty;
      case QuestionType.judge:
        return userAnswer is bool;
      case QuestionType.fill:
        return userAnswer is Iterable &&
            userAnswer.any((answer) => answer.toString().trim().isNotEmpty);
      case QuestionType.shortAnswer:
        return userAnswer is String && userAnswer.trim().isNotEmpty;
    }
  }

  static AnswerStatus evaluate(Question question, dynamic userAnswer) {
    if (!isAnswered(question, userAnswer)) {
      return AnswerStatus.unanswered;
    }

    switch (question.type) {
      case QuestionType.choice:
        return userAnswer == question.answer
            ? AnswerStatus.correct
            : AnswerStatus.incorrect;
      case QuestionType.multi:
        return _iterablesContainSameValues(userAnswer, question.answer)
            ? AnswerStatus.correct
            : AnswerStatus.incorrect;
      case QuestionType.judge:
        return userAnswer == question.answer
            ? AnswerStatus.correct
            : AnswerStatus.incorrect;
      case QuestionType.fill:
        return _fillAnswersMatch(userAnswer, question.answer)
            ? AnswerStatus.correct
            : AnswerStatus.incorrect;
      case QuestionType.shortAnswer:
        return AnswerStatus.pendingReview;
    }
  }

  static QuizResult summarize(
    List<Question> questions,
    Map<String, dynamic> userAnswers,
  ) {
    var correct = 0;
    var incorrect = 0;
    var unanswered = 0;
    var pendingReview = 0;

    for (final question in questions) {
      switch (evaluate(question, userAnswers[question.id])) {
        case AnswerStatus.correct:
          correct++;
        case AnswerStatus.incorrect:
          incorrect++;
        case AnswerStatus.unanswered:
          unanswered++;
        case AnswerStatus.pendingReview:
          pendingReview++;
      }
    }

    return QuizResult(
      total: questions.length,
      correct: correct,
      incorrect: incorrect,
      unanswered: unanswered,
      pendingReview: pendingReview,
      autoGradableTotal: questions
          .where((question) => question.type != QuestionType.shortAnswer)
          .length,
    );
  }

  static String referenceAnswer(Question question) {
    switch (question.type) {
      case QuestionType.choice:
        final answer = question.answer;
        if (answer is int && answer >= 0 && answer < question.options.length) {
          return '${String.fromCharCode(65 + answer)}. ${question.options[answer]}';
        }
        return answer.toString();
      case QuestionType.multi:
        if (question.answer is! Iterable) {
          return question.answer.toString();
        }
        return (question.answer as Iterable).map((answer) {
          if (answer is int &&
              answer >= 0 &&
              answer < question.options.length) {
            return '${String.fromCharCode(65 + answer)}. ${question.options[answer]}';
          }
          return answer.toString();
        }).join('、');
      case QuestionType.judge:
        return question.answer == true ? '正确' : '错误';
      case QuestionType.fill:
        if (question.answer is Iterable) {
          return (question.answer as Iterable).join(' / ');
        }
        return question.answer.toString();
      case QuestionType.shortAnswer:
        return question.answer.toString();
    }
  }

  static bool _iterablesContainSameValues(dynamic first, dynamic second) {
    if (first is! Iterable || second is! Iterable) {
      return false;
    }
    final firstSet = first.toSet();
    final secondSet = second.toSet();
    return firstSet.length == secondSet.length &&
        firstSet.containsAll(secondSet);
  }

  static bool _fillAnswersMatch(dynamic userAnswer, dynamic correctAnswer) {
    if (userAnswer is! Iterable || correctAnswer is! Iterable) {
      return false;
    }
    final userAnswers = userAnswer
        .map((answer) => answer.toString().trim())
        .toList(growable: false);
    final correctAnswers = correctAnswer
        .map((answer) => answer.toString().trim())
        .toList(growable: false);

    if (userAnswers.length != correctAnswers.length) {
      return false;
    }

    for (var index = 0; index < correctAnswers.length; index++) {
      if (userAnswers[index] != correctAnswers[index]) {
        return false;
      }
    }
    return true;
  }
}
