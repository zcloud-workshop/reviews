/// 题目类型
enum QuestionType {
  choice, // 单选
  multi, // 多选
  judge, // 判断
  fill, // 填空
  shortAnswer, // 简答
}

/// 题目模型
class Question {
  final String id;
  final QuestionType type;
  final String content;
  final List<String> options;
  final dynamic answer;

  Question({
    required this.id,
    required this.type,
    required this.content,
    this.options = const [],
    required this.answer,
  });
}

/// 练习组模型
class QuizDay {
  final String id;
  final String title;
  final List<Question> questions;

  QuizDay({
    required this.id,
    required this.title,
    required this.questions,
  });
}

/// 模块模型
class QuizModule {
  final String id;
  final String name;
  final String description;
  final List<QuizDay> days;

  QuizModule({
    required this.id,
    required this.name,
    required this.description,
    required this.days,
  });
}
