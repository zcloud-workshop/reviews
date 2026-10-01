import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reviews/data/sample_data.dart';
import 'package:reviews/models/question_bank_import.dart';
import 'package:reviews/models/quiz.dart';
import 'package:reviews/screens/quiz_screen.dart';
import 'package:reviews/services/answer_evaluator.dart';
import 'package:reviews/services/question_bank_codec.dart';
import 'package:reviews/services/question_bank_controller.dart';
import 'package:reviews/services/question_bank_repository.dart';
import 'package:reviews/services/quiz_progress_controller.dart';
import 'package:reviews/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('判题器可以统计自动判分题和待核对简答题', () {
    final questions = [
      Question(
        id: 'choice',
        type: QuestionType.choice,
        content: '单选',
        options: const ['A', 'B'],
        answer: 1,
      ),
      Question(
        id: 'multi',
        type: QuestionType.multi,
        content: '多选',
        options: const ['A', 'B', 'C'],
        answer: [0, 1],
      ),
      Question(
        id: 'judge',
        type: QuestionType.judge,
        content: '判断',
        answer: true,
      ),
      Question(
        id: 'fill',
        type: QuestionType.fill,
        content: '填空',
        answer: ['答案'],
      ),
      Question(
        id: 'short',
        type: QuestionType.shortAnswer,
        content: '简答',
        answer: '参考内容',
      ),
    ];
    final answers = <String, dynamic>{
      'choice': 1,
      'multi': [1, 0],
      'judge': false,
      'fill': [' 答案 '],
      'short': '我的回答',
    };

    final result = AnswerEvaluator.summarize(questions, answers);

    expect(result.total, 5);
    expect(result.correct, 3);
    expect(result.incorrect, 1);
    expect(result.unanswered, 0);
    expect(result.pendingReview, 1);
    expect(result.autoGradableTotal, 4);
    expect(result.accuracy, 0.75);
  });

  testWidgets('主题按钮只在白天和夜间切换并保存选择', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _pumpApp(tester);

    ThemeMode currentMode() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

    expect(currentMode(), ThemeMode.light);
    expect(find.text('跟随系统'), findsNothing);
    expect(find.byTooltip('切换到夜间模式'), findsOneWidget);

    await tester.tap(find.byTooltip('切换到夜间模式'));
    await tester.pumpAndSettle();
    expect(currentMode(), ThemeMode.dark);
    expect(
      (await SharedPreferences.getInstance()).getString('theme_mode'),
      'dark',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpApp(tester);
    expect(currentMode(), ThemeMode.dark);
    expect(find.byTooltip('切换到白天模式'), findsOneWidget);
  });

  testWidgets('可以从首页进入第一组练习', (tester) async {
    await _seedSampleModule();
    await _pumpApp(tester);

    expect(find.text('Reviews'), findsOneWidget);
    expect(find.text('新一代信息技术'), findsOneWidget);
    expect(find.text('5 题 · 0/2 组完成'), findsOneWidget);

    await _openFirstQuiz(tester);

    expect(find.text('共 3 道题'), findsOneWidget);
    expect(find.text('已答 0 · 自动保存'), findsOneWidget);
    expect(find.textContaining('一个字节'), findsOneWidget);
    await _scrollToSubmit(tester);
    expect(find.text('提交答案'), findsOneWidget);
  });

  testWidgets('草稿自动保存并在重启后恢复为进行中', (tester) async {
    await _seedSampleModule();
    await _pumpApp(tester);
    await _openFirstQuiz(tester);

    await tester.tap(find.text('8 位'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('已答 1 · 自动保存'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('进行中'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('5 题 · 0/2 组完成'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpApp(tester);
    await _openFirstQuiz(tester);

    expect(find.text('已答 1 · 自动保存'), findsOneWidget);
  });

  testWidgets('提交结果、完成状态和正确率可以跨重启恢复', (tester) async {
    await _seedSampleModule();
    await _pumpApp(tester);
    await _openFirstQuiz(tester);

    await tester.tap(find.text('8 位'));
    await _tapSubmit(tester);
    expect(find.textContaining('还有 2 道题未作答'), findsOneWidget);

    await tester.tap(find.text('继续提交'));
    await tester.pumpAndSettle();
    await _scrollToTop(tester);
    expect(find.text('本组结果'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('已完成 33%'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('5 题 · 1/2 组完成'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpApp(tester);
    await _openFirstQuiz(tester);

    expect(find.text('本组结果'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('重新做题'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('重新做题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('上一次成绩会保留'), findsOneWidget);
    expect(find.text('开始重做'), findsOneWidget);

    await tester.tap(find.text('开始重做'));
    await tester.pumpAndSettle();
    expect(find.text('提交答案'), findsOneWidget);
    expect(find.text('重新做题'), findsNothing);
  });

  testWidgets('简答题提交后显示参考答案并标记待核对', (tester) async {
    final progressController = QuizProgressController();
    await progressController.load();
    addTearDown(progressController.dispose);
    final day = QuizDay(
      id: 'short-day',
      title: '简答练习',
      questions: [
        Question(
          id: 'short',
          type: QuestionType.shortAnswer,
          content: '请简要说明测试的作用。',
          answer: '测试用于验证软件行为是否符合预期。',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(
          day: day,
          progressController: progressController,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '我的回答');
    await _tapSubmit(tester);
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(find.text('简答题待自行核对'), findsOneWidget);
    expect(find.text('待核对 1'), findsOneWidget);
    expect(
      find.text('参考答案：测试用于验证软件行为是否符合预期。'),
      findsOneWidget,
    );
  });

  test('JSON 题库可以解析五种题型并统计预览信息', () {
    final preview = QuestionBankCodec.decode(_validQuestionBankJson);

    expect(preview.modules, hasLength(1));
    expect(preview.dayCount, 1);
    expect(preview.questionCount, 5);
    expect(
      preview.modules.single.days.single.questions
          .map((question) => question.type),
      containsAll(<QuestionType>[
        QuestionType.choice,
        QuestionType.multi,
        QuestionType.judge,
        QuestionType.fill,
        QuestionType.shortAnswer,
      ]),
    );
  });

  test('JSON 题库校验会返回可定位的题目错误', () {
    const invalidJson = '''
{
  "formatVersion": 1,
  "modules": [{
    "id": "module-1",
    "name": "错误题库",
    "days": [{
      "id": "day-1",
      "title": "练习",
      "questions": [{
        "id": "q-1",
        "type": "choice",
        "content": "错误题",
        "options": ["A", "B"],
        "answer": 2
      }]
    }]
  }]
}
''';

    expect(
      () => QuestionBankCodec.decode(invalidJson),
      throwsA(
        isA<QuestionBankImportException>().having(
          (error) => error.errors.join('\n'),
          'errors',
          contains('模块 1 / 练习组 1 / 第 1 题.answer'),
        ),
      ),
    );
  });

  test('导入题库可以本地保存、重启恢复并安全另存冲突模块', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = QuestionBankRepository(preferences: preferences);
    final preview = QuestionBankCodec.decode(_validQuestionBankJson);
    final controller = QuestionBankController(repository: repository);
    await controller.load();

    await controller.importModules(
      preview.modules,
      strategy: QuestionBankConflictStrategy.keepBoth,
    );
    expect(controller.importedModules.single.name, '网络基础');

    final restored = QuestionBankController(repository: repository);
    await restored.load();
    expect(restored.importedModules.single.days.single.questions, hasLength(5));

    const conflictingJson = '''
{
  "formatVersion": 1,
  "modules": [{
    "id": "sample-1",
    "name": "新一代信息技术",
    "days": [{
      "id": "day-1",
      "title": "导入练习",
      "questions": [{
        "id": "q-1",
        "type": "judge",
        "content": "导入题目",
        "answer": true
      }]
    }]
  }]
}
''';
    final conflictPreview = QuestionBankCodec.decode(conflictingJson);
    await restored.importModules(
      conflictPreview.modules,
      strategy: QuestionBankConflictStrategy.keepBoth,
    );
    await restored.importModules(
      conflictPreview.modules,
      strategy: QuestionBankConflictStrategy.keepBoth,
    );

    final importedConflict = restored.importedModules.last;
    expect(importedConflict.name, '新一代信息技术（导入 1）');
    expect(importedConflict.id, 'sample-1-import-1');
    expect(importedConflict.days.single.id, contains('sample-1-import-1'));
    expect(
      importedConflict.days.single.questions.single.id,
      contains('sample-1-import-1'),
    );
  });
}

Future<void> _seedSampleModule() async {
  final preferences = await SharedPreferences.getInstance();
  await QuestionBankRepository(preferences: preferences)
      .saveImportedModules([SampleData.modules.first]);
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ReviewsApp());
  await tester.pumpAndSettle();
}

Future<void> _openFirstQuiz(WidgetTester tester) async {
  await tester.tap(find.text('新一代信息技术'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Day 1'));
  await tester.pumpAndSettle();
}

Future<void> _scrollToSubmit(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('提交答案'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await _scrollToSubmit(tester);
  await tester.tap(find.text('提交答案'));
  await tester.pumpAndSettle();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.fling(
    find.byType(ListView),
    const Offset(0, 1000),
    1200,
  );
  await tester.pumpAndSettle();
}

const _validQuestionBankJson = '''
{
  "formatVersion": 1,
  "modules": [{
    "id": "network-basics",
    "name": "网络基础",
    "description": "导入测试题库",
    "days": [{
      "id": "network-day-1",
      "title": "基础练习",
      "questions": [
        {
          "id": "network-choice-1",
          "type": "choice",
          "content": "HTTP 默认端口是？",
          "options": ["21", "53", "80", "443"],
          "answer": 2
        },
        {
          "id": "network-multi-1",
          "type": "multi",
          "content": "哪些是应用层协议？",
          "options": ["HTTP", "TCP", "DNS", "IP"],
          "answer": [0, 2]
        },
        {
          "id": "network-judge-1",
          "type": "judge",
          "content": "HTTPS 使用 TLS/SSL。",
          "answer": true
        },
        {
          "id": "network-fill-1",
          "type": "fill",
          "content": "IPv4 有 ______ 位。",
          "answer": ["32"]
        },
        {
          "id": "network-short-1",
          "type": "shortAnswer",
          "content": "DNS 的作用是什么？",
          "answer": "将域名解析为 IP 地址。"
        }
      ]
    }]
  }]
}
''';
