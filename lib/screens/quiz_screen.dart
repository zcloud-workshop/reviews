import 'dart:async';

import 'package:flutter/material.dart';

import '../models/quiz.dart';
import '../services/answer_evaluator.dart';
import '../services/quiz_progress_controller.dart';
import '../theme/app_theme.dart';

class QuizScreen extends StatefulWidget {
  final QuizDay day;
  final QuizProgressController progressController;

  const QuizScreen({
    super.key,
    required this.day,
    required this.progressController,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final Map<String, dynamic> userAnswers = {};
  Timer? _draftTimer;
  bool submitted = false;
  bool _hasDraftChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final progress = widget.progressController.progressFor(widget.day.id);
    if (progress != null) {
      userAnswers.addAll(
        progress.answers.map(
          (questionId, answer) => MapEntry(
            questionId,
            answer is List ? List<dynamic>.from(answer) : answer,
          ),
        ),
      );
      submitted = progress.submitted;
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (!submitted && _hasDraftChanges) {
      unawaited(_saveDraft());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final answered = widget.day.questions
        .where(
          (question) => AnswerEvaluator.isAnswered(
            question,
            userAnswers[question.id],
          ),
        )
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(widget.day.title)),
      body: AbsorbPointer(
        absorbing: _isSaving,
        child: widget.day.questions.isEmpty
            ? const _EmptyQuizView()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: widget.day.questions.length + 2,
                itemBuilder: (context, itemIndex) {
                  if (itemIndex == 0) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(
                                '共 ${widget.day.questions.length} 道题',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                submitted ? '已完成' : '已答 $answered · 自动保存',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: submitted
                                      ? AppTheme.green
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          if (submitted) ...[
                            const SizedBox(height: 12),
                            _QuizResultCard(
                              result: AnswerEvaluator.summarize(
                                widget.day.questions,
                                userAnswers,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ]);
                  }
                  if (itemIndex <= widget.day.questions.length) {
                    final index = itemIndex - 1;
                    final question = widget.day.questions[index];
                    return _QuestionCard(
                      key: ValueKey(question.id),
                      index: index,
                      question: question,
                      userAnswer: userAnswers[question.id],
                      submitted: submitted,
                      onAnswer: (answer) => _recordAnswer(question, answer),
                    );
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 6),
                        if (!submitted)
                          ElevatedButton(
                            onPressed: _showSubmitDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: const Text(
                              '提交答案',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (submitted)
                          ElevatedButton(
                            onPressed: _showRetryDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: const Text(
                              '重新做题',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                      ]);
                },
              ),
      ),
    );
  }

  void _recordAnswer(Question question, dynamic answer) {
    if (submitted || _isSaving) {
      return;
    }
    setState(() {
      if (AnswerEvaluator.isAnswered(question, answer)) {
        userAnswers[question.id] = answer;
      } else {
        userAnswers.remove(question.id);
      }
      _hasDraftChanges = true;
    });
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 350), () {
      if (!_hasDraftChanges) {
        return;
      }
      unawaited(_saveDraft());
    });
  }

  Future<void> _saveDraft() async {
    _hasDraftChanges = false;
    try {
      await widget.progressController.saveDraft(widget.day.id, userAnswers);
    } catch (_) {
      _hasDraftChanges = true;
      if (mounted) _showSaveError('草稿保存失败, 请重试.');
    }
  }

  void _showSaveError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showSubmitDialog() async {
    final unanswered = widget.day.questions
        .where(
          (question) => !AnswerEvaluator.isAnswered(
            question,
            userAnswers[question.id],
          ),
        )
        .length;

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('提交确认'),
        content: Text(
          unanswered == 0
              ? '确定提交本组答案？'
              : '还有 $unanswered 道题未作答。你可以返回补答，也可以继续提交。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(unanswered == 0 ? '取消' : '返回补答'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(unanswered == 0 ? '确认提交' : '继续提交'),
          ),
        ],
      ),
    );

    if (shouldSubmit == true && mounted) {
      _draftTimer?.cancel();
      _hasDraftChanges = false;
      final result = AnswerEvaluator.summarize(
        widget.day.questions,
        userAnswers,
      );
      FocusScope.of(context).unfocus();
      setState(() => _isSaving = true);
      try {
        await widget.progressController.complete(
          widget.day.id,
          userAnswers,
          accuracy: result.accuracy,
        );
        if (mounted) setState(() => submitted = true);
      } catch (_) {
        _hasDraftChanges = true;
        if (mounted) _showSaveError('提交失败, 答案尚未保存. 请重试.');
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showRetryDialog() async {
    final shouldRetry = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新做题'),
        content: const Text(
          '将清空当前答案并开始新一轮练习。上一次成绩会保留，直到你提交新的成绩。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('开始重做'),
          ),
        ],
      ),
    );

    if (shouldRetry == true && mounted) {
      _draftTimer?.cancel();
      setState(() => _isSaving = true);
      try {
        await widget.progressController.saveDraft(widget.day.id, {});
        if (mounted) {
          setState(() {
            userAnswers.clear();
            submitted = false;
            _hasDraftChanges = false;
          });
        }
      } catch (_) {
        if (mounted) _showSaveError('开始重做失败, 请重试.');
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }
}

class _QuizResultCard extends StatelessWidget {
  final QuizResult result;

  const _QuizResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final percentage = (result.accuracy * 100).round();
    final hasAutoGradableQuestions = result.autoGradableTotal > 0;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.assessment_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Text(
                  '本组结果',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                Text(
                  hasAutoGradableQuestions ? '$percentage%' : '待核对',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hasAutoGradableQuestions
                  ? '自动判分正确率（${result.autoGradableTotal} 道）'
                  : '本组题目需要自行核对',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ResultStat(
                  label: '正确',
                  value: result.correct,
                  color: AppTheme.green,
                ),
                _ResultStat(
                  label: '错误',
                  value: result.incorrect,
                  color: AppTheme.red,
                ),
                _ResultStat(
                  label: '未答',
                  value: result.unanswered,
                  color: AppTheme.orange,
                ),
                if (result.pendingReview > 0)
                  _ResultStat(
                    label: '待核对',
                    value: result.pendingReview,
                    color: AppTheme.purple,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _ResultStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final int index;
  final Question question;
  final dynamic userAnswer;
  final bool submitted;
  final ValueChanged<dynamic> onAnswer;

  const _QuestionCard({
    super.key,
    required this.index,
    required this.question,
    required this.userAnswer,
    required this.submitted,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final status = AnswerEvaluator.evaluate(question, userAnswer);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                color: _getTypeColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _getTypeName(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _getTypeColor(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${index + 1}. ${question.content}',
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w600,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 16),
            if (question.type == QuestionType.choice)
              _ChoiceOptions(
                question: question,
                userAnswer: userAnswer,
                submitted: submitted,
                onAnswer: onAnswer,
              ),
            if (question.type == QuestionType.multi)
              _MultiOptions(
                question: question,
                userAnswer: userAnswer,
                submitted: submitted,
                onAnswer: onAnswer,
              ),
            if (question.type == QuestionType.judge)
              _JudgeOptions(
                question: question,
                userAnswer: userAnswer,
                submitted: submitted,
                onAnswer: onAnswer,
              ),
            if (question.type == QuestionType.fill)
              _FillAnswer(
                key: ValueKey('fill-${question.id}'),
                question: question,
                userAnswer: userAnswer,
                submitted: submitted,
                onAnswer: onAnswer,
              ),
            if (question.type == QuestionType.shortAnswer)
              _ShortAnswer(
                key: ValueKey('short-${question.id}'),
                userAnswer: userAnswer,
                submitted: submitted,
                onAnswer: onAnswer,
              ),
            if (submitted) ...[
              const SizedBox(height: 4),
              _QuestionFeedback(question: question, status: status),
            ],
          ],
        ),
      ),
    );
  }

  String _getTypeName() {
    switch (question.type) {
      case QuestionType.choice:
        return '单选题';
      case QuestionType.multi:
        return '多选题';
      case QuestionType.judge:
        return '判断题';
      case QuestionType.fill:
        return '填空题';
      case QuestionType.shortAnswer:
        return '简答题';
    }
  }

  Color _getTypeColor() {
    switch (question.type) {
      case QuestionType.choice:
      case QuestionType.multi:
        return AppTheme.blue;
      case QuestionType.judge:
        return AppTheme.orange;
      case QuestionType.fill:
        return AppTheme.purple;
      case QuestionType.shortAnswer:
        return AppTheme.green;
    }
  }
}

class _QuestionFeedback extends StatelessWidget {
  final Question question;
  final AnswerStatus status;

  const _QuestionFeedback({required this.question, required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color, title) = switch (status) {
      AnswerStatus.correct => (Icons.check_circle, AppTheme.green, '回答正确'),
      AnswerStatus.incorrect => (Icons.cancel, AppTheme.red, '回答错误'),
      AnswerStatus.unanswered => (
          Icons.warning_amber_rounded,
          AppTheme.orange,
          '未作答'
        ),
      AnswerStatus.pendingReview => (
          Icons.fact_check_outlined,
          AppTheme.purple,
          '简答题待自行核对'
        ),
    };
    final showReference = status != AnswerStatus.correct;

    return Semantics(
      liveRegion: true,
      label: showReference
          ? '$title，参考答案：${AnswerEvaluator.referenceAnswer(question)}'
          : title,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (showReference) ...[
                    const SizedBox(height: 3),
                    Text(
                      '参考答案：${AnswerEvaluator.referenceAnswer(question)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceOptions extends StatelessWidget {
  final Question question;
  final dynamic userAnswer;
  final bool submitted;
  final ValueChanged<dynamic> onAnswer;

  const _ChoiceOptions({
    required this.question,
    required this.userAnswer,
    required this.submitted,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: question.options.asMap().entries.map((entry) {
        final index = entry.key;
        final option = entry.value;
        final isSelected = userAnswer == index;
        final isCorrect = question.answer == index;
        final isWrong = submitted && isSelected && !isCorrect;
        final colors = _optionColors(
          context,
          isSelected: isSelected,
          isCorrect: submitted && isCorrect,
          isWrong: isWrong,
        );

        return _OptionTile(
          semanticLabel: '选项 ${String.fromCharCode(65 + index)}，$option',
          selected: isSelected,
          enabled: !submitted,
          label: String.fromCharCode(65 + index),
          text: option,
          colors: colors,
          trailing: submitted && isCorrect
              ? Icon(Icons.check, color: AppTheme.green)
              : isWrong
                  ? Icon(Icons.close, color: AppTheme.red)
                  : null,
          onTap: () => onAnswer(index),
        );
      }).toList(),
    );
  }
}

class _MultiOptions extends StatelessWidget {
  final Question question;
  final dynamic userAnswer;
  final bool submitted;
  final ValueChanged<dynamic> onAnswer;

  const _MultiOptions({
    required this.question,
    required this.userAnswer,
    required this.submitted,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final selected = userAnswer is Iterable
        ? Set<dynamic>.from(userAnswer as Iterable)
        : <dynamic>{};
    final correct = question.answer is Iterable
        ? Set<dynamic>.from(question.answer as Iterable)
        : <dynamic>{};

    return Column(
      children: question.options.asMap().entries.map((entry) {
        final index = entry.key;
        final option = entry.value;
        final isSelected = selected.contains(index);
        final isCorrect = correct.contains(index);
        final isWrong = submitted && isSelected && !isCorrect;
        final colors = _optionColors(
          context,
          isSelected: isSelected,
          isCorrect: submitted && isCorrect,
          isWrong: isWrong,
        );

        return _OptionTile(
          semanticLabel: '选项 ${String.fromCharCode(65 + index)}，$option',
          selected: isSelected,
          enabled: !submitted,
          label: String.fromCharCode(65 + index),
          text: option,
          colors: colors,
          trailing: submitted && isCorrect
              ? Icon(Icons.check, color: AppTheme.green)
              : isWrong
                  ? Icon(Icons.close, color: AppTheme.red)
                  : null,
          onTap: () {
            final newSelected = Set<dynamic>.from(selected);
            if (isSelected) {
              newSelected.remove(index);
            } else {
              newSelected.add(index);
            }
            onAnswer(newSelected.cast<int>().toList()..sort());
          },
        );
      }).toList(),
    );
  }
}

class _OptionColors {
  final Color background;
  final Color border;
  final Color text;
  final Color labelBackground;
  final Color labelForeground;

  const _OptionColors({
    required this.background,
    required this.border,
    required this.text,
    required this.labelBackground,
    required this.labelForeground,
  });
}

_OptionColors _optionColors(
  BuildContext context, {
  required bool isSelected,
  required bool isCorrect,
  required bool isWrong,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  var accent = colorScheme.outlineVariant;
  var background = Colors.transparent;
  var text = colorScheme.onSurface;
  var labelBackground = colorScheme.surfaceContainerHighest;
  var labelForeground = colorScheme.onSurface;

  if (isCorrect) {
    accent = AppTheme.green;
    background = AppTheme.green.withValues(alpha: 0.1);
    text = AppTheme.green;
    labelBackground = AppTheme.green;
    labelForeground = Colors.white;
  } else if (isWrong) {
    accent = AppTheme.red;
    background = AppTheme.red.withValues(alpha: 0.1);
    text = AppTheme.red;
    labelBackground = AppTheme.red;
    labelForeground = Colors.white;
  } else if (isSelected) {
    accent = AppTheme.blue;
    background = AppTheme.blue.withValues(alpha: 0.1);
    labelBackground = AppTheme.blue;
    labelForeground = Colors.white;
  }

  return _OptionColors(
    background: background,
    border: accent,
    text: text,
    labelBackground: labelBackground,
    labelForeground: labelForeground,
  );
}

class _OptionTile extends StatelessWidget {
  final String semanticLabel;
  final bool selected;
  final bool enabled;
  final String label;
  final String text;
  final _OptionColors colors;
  final Widget? trailing;
  final VoidCallback onTap;

  const _OptionTile({
    required this.semanticLabel,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.text,
    required this.colors,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.background,
                border: Border.all(color: colors.border, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: colors.labelBackground,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colors.labelForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(fontSize: 15, color: colors.text),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JudgeOptions extends StatelessWidget {
  final Question question;
  final dynamic userAnswer;
  final bool submitted;
  final ValueChanged<dynamic> onAnswer;

  const _JudgeOptions({
    required this.question,
    required this.userAnswer,
    required this.submitted,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _JudgeOption(
            label: '正确',
            value: true,
            selected: userAnswer == true,
            correct: question.answer == true,
            submitted: submitted,
            onTap: () => onAnswer(true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _JudgeOption(
            label: '错误',
            value: false,
            selected: userAnswer == false,
            correct: question.answer == false,
            submitted: submitted,
            onTap: () => onAnswer(false),
          ),
        ),
      ],
    );
  }
}

class _JudgeOption extends StatelessWidget {
  final String label;
  final bool value;
  final bool selected;
  final bool correct;
  final bool submitted;
  final VoidCallback onTap;

  const _JudgeOption({
    required this.label,
    required this.value,
    required this.selected,
    required this.correct,
    required this.submitted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = submitted && correct;
    final isWrong = submitted && selected && !correct;
    final colors = _optionColors(
      context,
      isSelected: selected,
      isCorrect: isCorrect,
      isWrong: isWrong,
    );

    return Semantics(
      button: true,
      selected: selected,
      enabled: !submitted,
      label: '判断为$label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: submitted ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border.all(color: colors.border, width: 2.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  value ? Icons.check : Icons.close,
                  size: 20,
                  color: colors.text,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FillAnswer extends StatefulWidget {
  final Question question;
  final dynamic userAnswer;
  final bool submitted;
  final ValueChanged<dynamic> onAnswer;

  const _FillAnswer({
    super.key,
    required this.question,
    required this.userAnswer,
    required this.submitted,
    required this.onAnswer,
  });

  @override
  State<_FillAnswer> createState() => _FillAnswerState();
}

class _FillAnswerState extends State<_FillAnswer> {
  late List<TextEditingController> _controllers;

  List<String> get _correctAnswers => widget.question.answer is Iterable
      ? (widget.question.answer as Iterable)
          .map((answer) => answer.toString())
          .toList(growable: false)
      : <String>[widget.question.answer.toString()];

  @override
  void initState() {
    super.initState();
    _createControllers();
  }

  @override
  void didUpdateWidget(covariant _FillAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final answerCountChanged = _controllers.length != _correctAnswers.length;
    final wasReset = oldWidget.submitted && !widget.submitted;
    final questionChanged = oldWidget.question.id != widget.question.id;

    if (answerCountChanged || wasReset || questionChanged) {
      _disposeControllers();
      _createControllers();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _createControllers() {
    final incoming = widget.userAnswer is Iterable
        ? (widget.userAnswer as Iterable)
            .map((answer) => answer.toString())
            .toList(growable: false)
        : const <String>[];
    _controllers = List.generate(
      _correctAnswers.length,
      (index) => TextEditingController(
        text: index < incoming.length ? incoming[index] : '',
      ),
    );
  }

  void _disposeControllers() {
    for (final controller in _controllers) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final correctAnswers = _correctAnswers;

    return Column(
      children: List.generate(correctAnswers.length, (index) {
        final userAnswer = _controllers[index].text.trim();
        final isCorrect = userAnswer == correctAnswers[index].trim();

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _controllers[index],
            readOnly: widget.submitted,
            onChanged: widget.submitted
                ? null
                : (_) => widget.onAnswer(
                      _controllers
                          .map((controller) => controller.text)
                          .toList(growable: false),
                    ),
            decoration: InputDecoration(
              labelText: '第 ${index + 1} 个空',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              filled: widget.submitted,
              fillColor: widget.submitted
                  ? (isCorrect ? AppTheme.green : AppTheme.red)
                      .withValues(alpha: 0.1)
                  : null,
              suffixIcon: widget.submitted
                  ? Icon(
                      isCorrect ? Icons.check : Icons.close,
                      color: isCorrect ? AppTheme.green : AppTheme.red,
                    )
                  : null,
              helperText: widget.submitted && !isCorrect
                  ? '参考答案：${correctAnswers[index]}'
                  : null,
              helperMaxLines: 2,
            ),
          ),
        );
      }),
    );
  }
}

class _ShortAnswer extends StatefulWidget {
  final dynamic userAnswer;
  final bool submitted;
  final ValueChanged<dynamic> onAnswer;

  const _ShortAnswer({
    super.key,
    required this.userAnswer,
    required this.submitted,
    required this.onAnswer,
  });

  @override
  State<_ShortAnswer> createState() => _ShortAnswerState();
}

class _ShortAnswerState extends State<_ShortAnswer> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.userAnswer?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _ShortAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.submitted && !widget.submitted) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      readOnly: widget.submitted,
      minLines: 3,
      maxLines: 6,
      onChanged: widget.submitted ? null : widget.onAnswer,
      decoration: InputDecoration(
        hintText: '请输入你的答案',
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _EmptyQuizView extends StatelessWidget {
  const _EmptyQuizView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.quiz_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            const Text(
              '本组暂无题目',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '返回上一页选择其他练习组吧。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回练习组'),
            ),
          ],
        ),
      ),
    );
  }
}
