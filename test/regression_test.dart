import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reviews/models/quiz.dart';
import 'package:reviews/models/quiz_progress.dart';
import 'package:reviews/screens/home_screen.dart';
import 'package:reviews/screens/quiz_screen.dart';
import 'package:reviews/services/document_question_bank_parser.dart';
import 'package:reviews/services/question_bank_controller.dart';
import 'package:reviews/services/question_bank_repository.dart';
import 'package:reviews/services/quiz_progress_controller.dart';
import 'package:reviews/services/quiz_progress_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_sharedChannel, null);
    messenger.setMockMethodCallHandler(_documentChannel, null);
  });

  test('填空题的 0 和 1 答案不会被识别为判断题', () {
    for (final answer in ['0', '1']) {
      final preview = DocumentQuestionBankParser.decode(
        '1. 数值为 ______\n答案：$answer',
        '数字.docx',
      );
      final question = preview.modules.single.days.single.questions.single;
      expect(question.type, QuestionType.fill);
      expect(question.answer, [answer]);
    }
    final judge = DocumentQuestionBankParser.decode(
      '1. 判断题：地球是圆的。\n答案：1',
      '判断.docx',
    );
    expect(judge.modules.single.days.single.questions.single.answer, true);
  });

  test('中文文件生成独立稳定的标识并保留 ASCII 文件标识', () {
    const text = '1. 请说明原因。\n答案：参考答案';
    final first = DocumentQuestionBankParser.decode(text, '数学.docx');
    final second = DocumentQuestionBankParser.decode(text, '英语.docx');
    final repeated = DocumentQuestionBankParser.decode(text, '数学.doc');
    expect(first.modules.single.id, isNot(second.modules.single.id));
    expect(first.modules.single.id, repeated.modules.single.id);
    expect(first.modules.single.days.single.id,
        isNot(second.modules.single.days.single.id));
    expect(
        DocumentQuestionBankParser.decode(text, 'My Bank.docx')
            .modules
            .single
            .id,
        'document-my-bank');
  });

  for (final conflict in ['day', 'question']) {
    test('另存导入会避开生成后的 $conflict 标识冲突并在重启后恢复', () async {
      final controller = QuestionBankController();
      addTearDown(controller.dispose);
      await controller.importModules([
        _module('base',
            dayId: conflict == 'day' ? 'base-import-1--day' : 'occupied-day',
            questionId: conflict == 'question'
                ? 'base-import-1--question'
                : 'occupied-question'),
      ], strategy: QuestionBankConflictStrategy.keepBoth);
      await controller.importModules([
        _module('base', dayId: 'day', questionId: 'question'),
      ], strategy: QuestionBankConflictStrategy.keepBoth);

      final restored = await QuestionBankRepository().loadImportedModules();
      expect(restored, hasLength(2));
      final dayIds = restored
          .expand((module) => module.days)
          .map((day) => day.id)
          .toList();
      final questionIds = restored
          .expand((module) => module.days)
          .expand((day) => day.questions)
          .map((question) => question.id)
          .toList();
      expect(dayIds.toSet(), hasLength(dayIds.length));
      expect(questionIds.toSet(), hasLength(questionIds.length));
    });
  }

  test('包含分隔符的原始标识另存后仍保持题目标识唯一', () async {
    final controller = QuestionBankController();
    addTearDown(controller.dispose);
    await controller.importModules([_module('base')],
        strategy: QuestionBankConflictStrategy.keepBoth);
    await controller.importModules([
      QuizModule(id: 'base', name: 'base', description: '', days: [
        _module('first', dayId: 'a--b', questionId: 'c').days.single,
        _module('second', dayId: 'a', questionId: 'b--c').days.single,
      ]),
    ], strategy: QuestionBankConflictStrategy.keepBoth);
    final restored = await QuestionBankRepository().loadImportedModules();
    expect(restored, hasLength(2));
    expect(restored.last.days, hasLength(2));
  });

  test('覆盖题库不会套用旧答案或旧成绩, 清理不影响其他模块', () async {
    final banks = QuestionBankController();
    final progress = QuizProgressController();
    addTearDown(banks.dispose);
    addTearDown(progress.dispose);
    final original = _module('base');
    final other = _module('other');
    await banks.importModules([original, other],
        strategy: QuestionBankConflictStrategy.keepBoth);
    await progress.complete(
        original.days.single.id, {original.days.single.questions.single.id: 1},
        accuracy: 1);
    await progress.complete(
        other.days.single.id, {other.days.single.questions.single.id: 1},
        accuracy: 1);

    await banks.importModules([_module('base', answer: 0)],
        strategy: QuestionBankConflictStrategy.replaceImported);
    final replaced = banks.modules.singleWhere((module) => module.id == 'base');
    expect(replaced.name, original.name);
    expect(replaced.days.single.id, isNot(original.days.single.id));
    expect(replaced.days.single.questions.single.id,
        isNot(original.days.single.questions.single.id));
    expect(progress.progressFor(replaced.days.single.id), isNull);
    await progress.clearForModule(original);
    final restored = await QuizProgressRepository().loadAll();
    expect(restored.keys, [other.days.single.id]);
    expect(await QuestionBankRepository().loadImportedModules(), hasLength(2));
  });

  test('导入和删除失败保留原题库, 后续写入可以重试', () async {
    final repository = _BankRepository();
    final controller = QuestionBankController(repository: repository);
    addTearDown(controller.dispose);
    await controller.importModules([_module('base')],
        strategy: QuestionBankConflictStrategy.keepBoth);
    var notifications = 0;
    controller.addListener(() => notifications++);
    repository.failWrites = true;
    await expectLater(
        controller.importModules([_module('base', answer: 0)],
            strategy: QuestionBankConflictStrategy.replaceImported),
        throwsStateError);
    await expectLater(
        controller.deleteImportedModule('base'), throwsStateError);
    expect(controller.modules.single.days.single.questions.single.answer, 1);
    expect(notifications, 0);
    expect((await repository.loadImportedModules()).single.id, 'base');

    repository.failWrites = false;
    await controller.importModules([_module('other')],
        strategy: QuestionBankConflictStrategy.keepBoth);
    expect(controller.modules, hasLength(2));
    await controller.deleteImportedModule('base');
    expect((await repository.loadImportedModules()).single.id, 'other');
  });

  test('连续导入在持久化成功后发布状态并保留所有模块', () async {
    final gate = Completer<void>();
    final repository = _BankRepository()..waitForSave = gate.future;
    final controller = QuestionBankController(repository: repository);
    addTearDown(controller.dispose);
    await controller.load();
    final first = controller.importModules([_module('base')],
        strategy: QuestionBankConflictStrategy.keepBoth);
    final second = controller.importModules([_module('base')],
        strategy: QuestionBankConflictStrategy.keepBoth);
    await Future<void>.delayed(Duration.zero);
    expect(controller.modules, isEmpty);
    gate.complete();
    await Future.wait([first, second]);
    expect(controller.modules, hasLength(2));
    expect(await repository.loadImportedModules(), hasLength(2));
  });

  test('进度保存和清理失败返回错误, 保留上次成功状态并允许重试', () async {
    final repository = _ProgressRepository();
    final controller = QuizProgressController(repository: repository);
    addTearDown(controller.dispose);
    final module = _module('base');
    final dayId = module.days.single.id;
    await controller.saveDraft(dayId, {'question': 0});
    repository.failWrites = true;
    await expectLater(controller.complete(dayId, {'question': 1}, accuracy: 1),
        throwsStateError);
    await expectLater(controller.clearForModule(module), throwsStateError);
    expect(controller.statusFor(dayId), QuizProgressStatus.inProgress);
    expect(controller.progressFor(dayId)!.answers, {'question': 0});
    expect((await repository.loadAll())[dayId]!.submitted, false);
    repository.failWrites = false;
    await controller.complete(dayId, {'question': 1}, accuracy: 1);
    expect(controller.statusFor(dayId), QuizProgressStatus.completed);
  });

  test('连续提交与草稿保存不会丢失成绩或引用随后修改的答案', () async {
    final controller = QuizProgressController();
    addTearDown(controller.dispose);
    final submitted = controller.complete(
        'day',
        {
          'q': [0]
        },
        accuracy: 1);
    final answers = <String, dynamic>{
      'q': [1]
    };
    final draft = controller.saveDraft('day', answers);
    (answers['q'] as List)[0] = 9;
    answers.clear();
    await Future.wait([submitted, draft]);
    final restored = (await QuizProgressRepository().loadAll())['day']!;
    expect(restored.answers, {
      'q': [1]
    });
    expect(restored.lastAccuracy, 1);
    expect(restored.submitted, false);
  });

  test('控制器销毁后仍完成排队写入, 不再通知界面', () async {
    final gate = Completer<void>();
    final banks = QuestionBankController(
        repository: _BankRepository()..waitForSave = gate.future);
    final progress = QuizProgressController(
        repository: _ProgressRepository()..waitForSave = gate.future);
    final bankWrite = banks.importModules([_module('base')],
        strategy: QuestionBankConflictStrategy.keepBoth);
    final progressWrite = progress.saveDraft('day', {'q': 1});
    banks.dispose();
    progress.dispose();
    gate.complete();
    await Future.wait([bankWrite, progressWrite]);
    expect(await QuestionBankRepository().loadImportedModules(), hasLength(1));
    expect(
        (await QuizProgressRepository().loadAll())['day']!.answers, {'q': 1});
  });

  test('存储返回 false 时题库和进度仓库都会报告失败', () async {
    final preferences = _RejectingPreferences();
    final banks = QuestionBankRepository(preferences: preferences);
    final progress = QuizProgressRepository(preferences: preferences);
    await expectLater(
        banks.saveImportedModules([_module('base')]), throwsStateError);
    await expectLater(banks.saveImportedModules([]), throwsStateError);
    await expectLater(progress.saveAll({}), throwsStateError);
  });

  test('没有匹配数据的删除和进度清理不发起无效写入', () async {
    final banks = QuestionBankController(
        repository: _BankRepository()..failWrites = true);
    final progress = QuizProgressController(
        repository: _ProgressRepository()..failWrites = true);
    addTearDown(banks.dispose);
    addTearDown(progress.dispose);
    expect(await banks.deleteImportedModule('missing'), isNull);
    await progress.clearForModule(_module('missing'));
  });

  testWidgets('提交失败不会丢失简答输入或显示已完成, 重试后保存成功', (tester) async {
    final repository = _ProgressRepository();
    final controller = QuizProgressController(repository: repository);
    addTearDown(controller.dispose);
    final day = _shortDay();
    await controller.load();
    await _pumpQuiz(tester, controller, day);
    await tester.enterText(find.byType(TextField), '保留我的回答');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    repository.failWrites = true;
    await _submitQuiz(tester);
    expect(find.text('提交失败, 答案尚未保存. 请重试.'), findsOneWidget);
    expect(find.text('本组结果'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留我的回答');
    expect(controller.progressFor(day.id)!.submitted, false);

    repository.failWrites = false;
    await _submitQuiz(tester);
    _scrollToStart(tester);
    await tester.pumpAndSettle();
    expect(find.text('本组结果'), findsOneWidget);
    expect((await repository.loadAll())[day.id]!.submitted, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('草稿保存失败会提示, 后续编辑可以正常保存', (tester) async {
    final repository = _ProgressRepository()..failWrites = true;
    final controller = QuizProgressController(repository: repository);
    addTearDown(controller.dispose);
    final day = _shortDay();
    await controller.load();
    await _pumpQuiz(tester, controller, day);
    await tester.enterText(find.byType(TextField), '第一次输入');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('草稿保存失败, 请重试.'), findsOneWidget);
    expect(controller.progressFor(day.id), isNull);
    expect(tester.takeException(), isNull);

    repository.failWrites = false;
    await tester.enterText(find.byType(TextField), '重试后的输入');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect((await repository.loadAll())[day.id]!.answers,
        {day.questions.single.id: '重试后的输入'});
  });

  testWidgets('开始重做后立即离开, 重启仍恢复为空白练习并保留上次成绩', (tester) async {
    final controller = QuizProgressController();
    addTearDown(controller.dispose);
    final day = _shortDay();
    await controller.complete(day.id, {day.questions.single.id: '旧答案'},
        accuracy: 1);
    await _pumpQuiz(tester, controller, day);
    await _retryQuiz(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final restored = QuizProgressController();
    addTearDown(restored.dispose);
    await restored.load();
    await _pumpQuiz(tester, restored, day);
    expect(find.text('本组结果'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(restored.progressFor(day.id)!.submitted, false);
    expect(restored.progressFor(day.id)!.answers, isEmpty);
    expect(restored.progressFor(day.id)!.lastAccuracy, 1);
  });

  testWidgets('重做状态保存失败时保留已提交结果', (tester) async {
    final repository = _ProgressRepository();
    final controller = QuizProgressController(repository: repository);
    addTearDown(controller.dispose);
    final day = _shortDay();
    await controller.complete(day.id, {day.questions.single.id: '旧答案'},
        accuracy: 1);
    await _pumpQuiz(tester, controller, day);
    repository.failWrites = true;
    await _retryQuiz(tester);
    expect(find.text('开始重做失败, 请重试.'), findsOneWidget);
    expect(controller.progressFor(day.id)!.submitted, true);
    expect(controller.progressFor(day.id)!.answers,
        {day.questions.single.id: '旧答案'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('长题库按需构建题目, 滚动返回后保留输入', (tester) async {
    final controller = QuizProgressController();
    addTearDown(controller.dispose);
    await controller.load();
    final day = QuizDay(id: 'long-day', title: '长题库', questions: [
      for (var index = 0; index < 100; index++)
        Question(
            id: 'long-$index',
            type: QuestionType.shortAnswer,
            content: '第 $index 题',
            answer: '参考答案'),
    ]);
    await _pumpQuiz(tester, controller, day);
    expect(find.byType(TextField).evaluate().length, lessThan(100));
    await tester.enterText(find.byType(TextField).first, '滚动前的答案');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('long-20')), 500,
        scrollable: find.byType(Scrollable).first);
    _scrollToStart(tester);
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '滚动前的答案');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(controller.progressFor(day.id)!.answers['long-0'], '滚动前的答案');
  });

  testWidgets('首页覆盖导入清理旧进度, 不影响其他模块', (tester) async {
    final banks = QuestionBankController();
    final progress = QuizProgressController();
    addTearDown(banks.dispose);
    addTearDown(progress.dispose);
    final original = DocumentQuestionBankParser.decode(
            _documentText.replaceFirst('答案：A', '答案：B'), '数学.doc')
        .modules
        .single;
    final other = _module('other');
    await banks.importModules([original, other],
        strategy: QuestionBankConflictStrategy.keepBoth);
    await progress.complete(
        original.days.single.id, {original.days.single.questions.single.id: 1},
        accuracy: 1);
    await progress.complete(
        other.days.single.id, {other.days.single.questions.single.id: 1},
        accuracy: 1);
    await _pumpSharedImport(tester, banks, progress);
    expect(find.textContaining('覆盖导入会清除'), findsOneWidget);
    await tester.tap(find.text('覆盖导入'));
    await tester.pumpAndSettle();
    final replacement =
        banks.modules.singleWhere((module) => module.id == original.id);
    expect(replacement.days.single.questions.single.answer, 0);
    expect(progress.progressFor(replacement.days.single.id), isNull);
    expect(progress.progressFor(original.days.single.id), isNull);
    expect((await QuizProgressRepository().loadAll()).keys,
        [other.days.single.id]);
    expect(find.textContaining('已导入 1 个模块'), findsOneWidget);
  });

  testWidgets('首页导入写入失败时显示失败并保留原题库', (tester) async {
    final repository = _BankRepository()..failWrites = true;
    final banks = QuestionBankController(repository: repository);
    final progress = QuizProgressController();
    addTearDown(banks.dispose);
    addTearDown(progress.dispose);
    await _pumpSharedImport(tester, banks, progress);
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    expect(find.text('导入失败, 题库未保存. 请重试.'), findsOneWidget);
    expect(banks.modules, isEmpty);
    expect(await repository.loadImportedModules(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连续分享文件依次预览和导入, 不会同时弹出多个预览', (tester) async {
    final banks = QuestionBankController();
    final progress = QuizProgressController();
    addTearDown(banks.dispose);
    addTearDown(progress.dispose);
    await _pumpSharedImport(tester, banks, progress);
    tester.binding.channelBuffers.push(
      _sharedChannel.name,
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('sharedFile', {
        'name': '英语.doc',
        'path': '/virtual/英语.doc',
      })),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '数学');
    await tester.tap(find.text('确认导入'));
    await tester.pump(const Duration(milliseconds: 300));
    await _waitForDialog(tester, '确认导入题库', moduleName: '英语');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '英语');
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    expect(banks.modules.map((module) => module.name), ['数学', '英语']);
    expect(await QuestionBankRepository().loadImportedModules(), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('后台解析的文档校验错误仍显示具体题目问题', (tester) async {
    final banks = QuestionBankController();
    final progress = QuizProgressController();
    addTearDown(banks.dispose);
    addTearDown(progress.dispose);
    await _pumpSharedImport(tester, banks, progress,
        documentText: '1. 缺少答案的题目', dialogTitle: '题库格式有误');
    expect(find.textContaining('第 1 题缺少答案'), findsOneWidget);
    expect(banks.modules, isEmpty);
  });

  testWidgets('覆盖后清理旧进度失败仍不会把旧成绩关联到新题库', (tester) async {
    final banks = QuestionBankController();
    final repository = _ProgressRepository();
    final progress = QuizProgressController(repository: repository);
    addTearDown(banks.dispose);
    addTearDown(progress.dispose);
    final original = DocumentQuestionBankParser.decode(_documentText, '数学.doc')
        .modules
        .single;
    await banks.importModules([original],
        strategy: QuestionBankConflictStrategy.keepBoth);
    await progress.complete(
        original.days.single.id, {original.days.single.questions.single.id: 0},
        accuracy: 1);
    repository.failWrites = true;
    await _pumpSharedImport(tester, banks, progress);
    await tester.tap(find.text('覆盖导入'));
    await tester.pumpAndSettle();
    expect(find.text('题库已导入, 但旧学习进度清理失败.'), findsOneWidget);
    expect(progress.progressFor(banks.modules.single.days.single.id), isNull);
    expect(progress.progressFor(original.days.single.id)!.submitted, true);
    expect(tester.takeException(), isNull);
  });
}

const _sharedChannel = MethodChannel('com.quiz.reviews/shared_file');
const _documentChannel = MethodChannel('com.quiz.reviews/document_reader');
const _documentText = '1. 请选择正确答案。\nA. 第一项\nB. 第二项\n答案：A';

QuizDay _shortDay() => QuizDay(id: 'short-day', title: '简答练习', questions: [
      Question(
          id: 'short-question',
          type: QuestionType.shortAnswer,
          content: '请说明原因',
          answer: '参考答案'),
    ]);

Future<void> _pumpQuiz(
    WidgetTester tester, QuizProgressController controller, QuizDay day) async {
  await tester.pumpWidget(
      MaterialApp(home: QuizScreen(day: day, progressController: controller)));
  await tester.pumpAndSettle();
}

Future<void> _submitQuiz(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('提交答案'), 300,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text('提交答案'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认提交'));
  await tester.pumpAndSettle();
}

Future<void> _retryQuiz(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('重新做题'), 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('重新做题'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始重做'));
  await tester.pumpAndSettle();
}

void _scrollToStart(WidgetTester tester) {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
}

Future<void> _pumpSharedImport(
  WidgetTester tester,
  QuestionBankController banks,
  QuizProgressController progress, {
  String documentText = _documentText,
  String dialogTitle = '确认导入题库',
}) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      _sharedChannel,
      (_) async => {
            'name': '数学.doc',
            'path': '/virtual/数学.doc',
          });
  messenger.setMockMethodCallHandler(
      _documentChannel, (_) async => documentText);
  await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
    themeMode: ThemeMode.light,
    onThemeModeChanged: (_) {},
    questionBankController: banks,
    progressController: progress,
  )));
  await _waitForDialog(tester, dialogTitle);
}

Future<void> _waitForDialog(WidgetTester tester, String title,
    {String? moduleName}) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      if (find.text(title).evaluate().isNotEmpty &&
          (moduleName == null ||
              find.byType(TextField).evaluate().any(
                    (element) =>
                        (element.widget as TextField).controller?.text ==
                        moduleName,
                  ))) {
        break;
      }
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text(title), findsOneWidget);
}

QuizModule _module(String id,
    {String? dayId, String? questionId, int answer = 1}) {
  return QuizModule(id: id, name: id, description: '', days: [
    QuizDay(id: dayId ?? '$id-day', title: '练习', questions: [
      Question(
          id: questionId ?? '$id-question',
          type: QuestionType.choice,
          content: '选择正确答案',
          options: ['A', 'B'],
          answer: answer),
    ]),
  ]);
}

class _BankRepository extends QuestionBankRepository {
  bool failWrites = false;
  Future<void>? waitForSave;

  @override
  Future<void> saveImportedModules(List<QuizModule> modules) async {
    await waitForSave;
    if (failWrites) throw StateError('写入失败');
    await super.saveImportedModules(modules);
  }
}

class _ProgressRepository extends QuizProgressRepository {
  bool failWrites = false;
  Future<void>? waitForSave;

  @override
  Future<void> saveAll(Map<String, QuizProgress> progresses) async {
    await waitForSave;
    if (failWrites) throw StateError('写入失败');
    await super.saveAll(progresses);
  }
}

class _RejectingPreferences implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  Future<bool> remove(String key) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
