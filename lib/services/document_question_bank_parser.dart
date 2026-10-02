import '../models/question_bank_import.dart';
import '../models/quiz.dart';

/// 将 Word 文档中的题目文本转换为应用使用的题库模型。
class DocumentQuestionBankParser {
  static const templatePrompt = '''请把题目整理成下面格式后，再保存为 .docx 或 .doc 导入：

【规则】
1. 每题必须以数字编号开头：1.、2、或 3）。
2. 选择题的选项必须各占一行：A. 内容、B. 内容、C. 内容。
3. 答案必须单独一行，并以“答案：”开头。
4. 多选题在题目中写“选择两项”或“选择多项”，答案写“AC”。
5. 判断题题目以“判断题：”开头，答案写“正确”或“错误”。
6. 填空题用连续 6 个以上下划线表示空格。
7. 简答题写出参考答案。
8. # 模块1、第1章等标题会被忽略。

【示例】
# 模块1：网络基础

1. HTTP 默认使用的端口是？（选择最佳答案。）
A. 21
B. 53
C. 80
D. 443
答案：C

2. 以下哪些属于应用层协议？（选择两项。）
A. HTTP
B. TCP
C. DNS
D. IP
答案：AC

3. 判断题：HTTPS 使用 TLS 加密。
答案：正确

4. IPv4 地址由 ______ 位二进制数组成。
答案：32

5. 简述 DNS 的作用。
答案：DNS 用于把域名解析为 IP 地址。''';

  const DocumentQuestionBankParser._();

  static QuestionBankImportPreview decode(String text, String fileName) {
    final parsed = _TextParser(text).parse();
    if (parsed.isEmpty) {
      throw const QuestionBankImportException([
        '没有识别到题目。题目请使用“1. 题目”、选项使用“A. 内容”、答案使用“答案：B”的格式。',
      ]);
    }

    final errors = <String>[];
    final questions = <Question>[];
    final moduleId = _stableId(fileName);
    for (var index = 0; index < parsed.length; index++) {
      final item = parsed[index];
      if (item.answer == null) {
        errors.add('第 ${index + 1} 题缺少答案。');
        continue;
      }
      final validationError = _validate(item);
      if (validationError != null) {
        errors.add('第 ${index + 1} 题$validationError');
        continue;
      }
      questions.add(
        Question(
          id: '$moduleId-question-${index + 1}',
          type: item.type,
          content: item.content,
          options: item.options,
          answer: item.answer,
        ),
      );
    }
    if (errors.isNotEmpty) throw QuestionBankImportException(errors);

    final moduleName = _fileStem(fileName).trim().isEmpty
        ? '文档题库'
        : _fileStem(fileName).trim();
    final dayId = '$moduleId-day-1';
    final module = QuizModule(
      id: moduleId,
      name: moduleName,
      description: '文档导入 · ${questions.length} 道题',
      days: [
        QuizDay(
          id: dayId,
          title: '文档题目',
          questions: questions,
        ),
      ],
    );

    return QuestionBankImportPreview(
      modules: [module],
      dayCount: 1,
      questionCount: questions.length,
    );
  }

  static String? _validate(_ParsedQuestion question) {
    switch (question.type) {
      case QuestionType.choice:
        return question.options.length < 2 ||
                question.answer is! int ||
                question.answer < 0 ||
                question.answer >= question.options.length
            ? '的选项或答案无效。'
            : null;
      case QuestionType.multi:
        final answers = question.answer;
        return question.options.length < 2 ||
                answers is! List ||
                answers.isEmpty ||
                answers.any(
                  (answer) =>
                      answer is! int ||
                      answer < 0 ||
                      answer >= question.options.length,
                ) ||
                answers.toSet().length != answers.length
            ? '的选项或答案无效。'
            : null;
      case QuestionType.judge:
        return question.answer is bool ? null : '的判断答案无效。';
      case QuestionType.fill:
        final answers = question.answer;
        return answers is List && answers.isNotEmpty ? null : '的填空答案无效。';
      case QuestionType.shortAnswer:
        return question.answer is String && question.answer.trim().isNotEmpty
            ? null
            : '的参考答案无效。';
    }
  }

  static String _fileStem(String fileName) => fileName.replaceFirst(
        RegExp(r'\.[^.]+$'),
        '',
      );

  static String _stableId(String fileName) {
    final stem = _fileStem(fileName).toLowerCase();
    if (RegExp(r'[^\x00-\x7f]').hasMatch(stem)) {
      return 'document-${Uri.encodeComponent(stem)}';
    }
    final ascii = stem.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final id = ascii.replaceAll(RegExp(r'^-+|-+$'), '');
    return 'document-${id.isEmpty ? 'bank' : id}';
  }
}

class _ParsedQuestion {
  final QuestionType type;
  final String content;
  final List<String> options;
  final dynamic answer;

  const _ParsedQuestion({
    required this.type,
    required this.content,
    required this.options,
    required this.answer,
  });
}

class _TextParser {
  static const _trueValues = ['对', '正确', '√', 'T', 'TRUE', '是', '1'];
  static const _falseValues = ['错', '错误', '×', 'F', 'FALSE', '否', '0'];

  final String source;

  const _TextParser(this.source);

  List<_ParsedQuestion> parse() {
    final lines = source
        .replaceAll('\u00a0', ' ')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final blocks = <List<String>>[];
    List<String>? current;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (_isChapter(line)) continue;
      if (_isQuestionStart(line, lines, index)) {
        if (current != null && current.isNotEmpty) blocks.add(current);
        current = [line];
      } else if (current != null) {
        current.add(line);
        if (_isAnswer(line)) {
          blocks.add(current);
          current = null;
        }
      }
    }
    if (current != null && current.isNotEmpty) blocks.add(current);
    return blocks.map(_parseBlock).whereType<_ParsedQuestion>().toList();
  }

  _ParsedQuestion? _parseBlock(List<String> lines) {
    var content = _questionText(lines.first);
    var rawAnswer = _inlineAnswer(lines.first);
    if (rawAnswer != null) {
      content = content.replaceFirst(RegExp(r'答案[：:].*$'), '').trim();
    }
    rawAnswer ??= _answer(lines);
    final options = lines
        .where(_isOption)
        .map((line) =>
            line.replaceFirst(RegExp(r'^[A-Za-z][\.、)）:：]\s*'), '').trim())
        .where((option) => option.isNotEmpty)
        .toList();
    if (content.isEmpty) return null;

    final type = _type(content, options, rawAnswer);
    return _ParsedQuestion(
      type: type,
      content: content,
      options: options,
      answer: _normalize(type, rawAnswer, options.length),
    );
  }

  bool _isChapter(String line) => RegExp(
        r'^(#+\s|第[一二三四五六七八九十\d]+[章节课]|模块\s*\d+)',
      ).hasMatch(line);

  bool _isQuestionStart(String line, List<String> lines, int index) {
    if (_isOption(line) || _isAnswer(line)) return false;
    if (RegExp(r'^\d+\s*[\.、)）\]]\s*').hasMatch(line) ||
        RegExp(r'^第\d+题\s*').hasMatch(line)) {
      return true;
    }
    if (RegExp(r'^[（(]\s*[）)]').hasMatch(line)) return true;
    if (RegExp(r'[（(]\s*[）)]').hasMatch(line)) {
      final next = index + 1 < lines.length ? lines[index + 1] : '';
      return _isOption(next) || _isAnswer(next);
    }
    return false;
  }

  bool _isOption(String line) =>
      RegExp(r'^[A-Za-z][\.、)）:：]\s*').hasMatch(line);

  bool _isAnswer(String line) {
    if (RegExp(r'^(答案|正确答案)[：:]').hasMatch(line)) return true;
    final value = line.trim().toUpperCase();
    return value.length <= 6 &&
        [..._trueValues, ..._falseValues].contains(value);
  }

  String _questionText(String line) => line
      .replaceFirst(RegExp(r'^\d+\s*[\.、)）\]]\s*'), '')
      .replaceFirst(RegExp(r'^第\d+题\s*'), '')
      .replaceFirst(RegExp(r'^判断题[：:]\s*'), '')
      .trim();

  String? _inlineAnswer(String line) =>
      RegExp(r'答案[：:]\s*(.+)').firstMatch(line)?.group(1)?.trim();

  String? _answer(List<String> lines) {
    for (final line in lines) {
      final answer =
          RegExp(r'(?:答案|正确答案)[：:]\s*(.+)').firstMatch(line)?.group(1)?.trim();
      if (answer != null && answer.isNotEmpty) return answer;
    }
    final last = lines.isEmpty ? '' : lines.last.trim();
    return _isJudgeValue(last) ? last : null;
  }

  QuestionType _type(String content, List<String> options, String? answer) {
    if (options.length >= 2) {
      final multiHint = RegExp(
        r'选择\s*(两|多|三|四|五|六|[2-6])\s*项',
      ).hasMatch(content);
      final compactAnswer = answer?.replaceAll(RegExp(r'[\s,，、]'), '') ?? '';
      return multiHint || RegExp(r'^[A-Za-z]{2,}$').hasMatch(compactAnswer)
          ? QuestionType.multi
          : QuestionType.choice;
    }
    if (RegExp(r'_{6,}').hasMatch(content)) return QuestionType.fill;
    if (RegExp(r'是否|能否|是非').hasMatch(content) ||
        RegExp(r'^判断题[：:]').hasMatch(content) ||
        _isJudgeValue(answer ?? '')) {
      return QuestionType.judge;
    }
    return QuestionType.shortAnswer;
  }

  bool _isJudgeValue(String value) {
    final normalized = value.trim().toUpperCase();
    return [..._trueValues, ..._falseValues].contains(normalized);
  }

  dynamic _normalize(QuestionType type, String? raw, int optionCount) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    switch (type) {
      case QuestionType.choice:
        final letter = RegExp(r'[A-Za-z]').firstMatch(value)?.group(0);
        if (letter != null) return letter.toUpperCase().codeUnitAt(0) - 65;
        final number = int.tryParse(value);
        return number != null && number >= 1 && number <= optionCount
            ? number - 1
            : null;
      case QuestionType.multi:
        final letters = RegExp(r'[A-Za-z]')
            .allMatches(value)
            .map((match) => match.group(0)!.toUpperCase().codeUnitAt(0) - 65)
            .toSet()
            .toList();
        if (letters.isNotEmpty) return letters;
        return value
            .split(RegExp(r'[、,，;；\s]+'))
            .where((part) => part.isNotEmpty)
            .map((part) => int.tryParse(part))
            .whereType<int>()
            .map((number) => number - 1)
            .toSet()
            .toList();
      case QuestionType.judge:
        return _trueValues.contains(value) ||
                _trueValues.contains(value.toUpperCase())
            ? true
            : _falseValues.contains(value) ||
                    _falseValues.contains(value.toUpperCase())
                ? false
                : null;
      case QuestionType.fill:
        return value
            .split(RegExp(r'[,，、;；]'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
      case QuestionType.shortAnswer:
        return value;
    }
  }
}
