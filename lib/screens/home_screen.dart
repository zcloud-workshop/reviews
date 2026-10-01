import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/question_bank_import.dart';
import '../models/quiz.dart';
import '../services/document_question_bank_parser.dart';
import '../services/json_file_picker.dart';
import '../services/question_bank_codec.dart';
import '../services/question_bank_controller.dart';
import '../services/quiz_progress_controller.dart';
import '../theme/app_theme.dart';
import 'module_screen.dart';

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final QuizProgressController progressController;
  final QuestionBankController questionBankController;

  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.progressController,
    required this.questionBankController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    SharedQuestionFileReceiver.listen(
      _onSharedFile,
      onError: _onSharedFileError,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSharedFile());
  }

  @override
  void dispose() {
    SharedQuestionFileReceiver.stop();
    super.dispose();
  }

  void _onSharedFile(PickedQuestionFile file) {
    _runImport(Future<PickedQuestionFile?>.value(file));
  }

  void _onSharedFileError(Object error) {
    if (!mounted) return;
    final message = error is FormatException
        ? error.message.toString()
        : 'QQ 文件读取失败，请确认文件是 .json、.docx 或 .doc。';
    _showMessage(message);
  }

  Future<void> _loadSharedFile() async {
    try {
      await Future.wait([
        widget.questionBankController.load(),
        widget.progressController.load(),
      ]);
      final file = await SharedQuestionFileReceiver.initial();
      if (mounted && file != null) {
        await _runImport(Future<PickedQuestionFile?>.value(file));
      }
    } on MissingPluginException {
      // 非 Android 平台没有 QQ 分享入口，忽略即可。
    } on FormatException catch (error) {
      if (mounted) {
        _showMessage(error.message.toString());
      }
    } catch (_) {
      // 普通启动时没有分享文件，或分享文件读取失败，不影响首页使用。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reviews',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: '文档格式模板',
            icon: const Icon(Icons.description_outlined),
            onPressed: _showDocumentTemplate,
          ),
          _ThemeModeButton(
            themeMode: widget.themeMode,
            onSelected: widget.onThemeModeChanged,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          widget.progressController,
          widget.questionBankController,
        ]),
        builder: (context, _) {
          if (!widget.progressController.isLoaded ||
              !widget.questionBankController.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          final modules = widget.questionBankController.modules;
          if (modules.isEmpty) {
            return const _EmptyModulesView();
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: modules.length,
            itemBuilder: (context, index) {
              final module = modules[index];
              return _ModuleCard(
                module: module,
                progressController: widget.progressController,
                onDelete:
                    widget.questionBankController.isImportedModule(module.id)
                        ? () => _confirmDeleteModule(module)
                        : null,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: '导入 JSON、Word 题库',
        onPressed: _isImporting ? null : _pickAndImport,
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.file_upload_outlined),
        label: Text(_isImporting ? '读取中' : '导入题库'),
      ),
    );
  }

  void _showDocumentTemplate() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('文档题库格式模板'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              DocumentQuestionBankParser.templatePrompt,
              style: const TextStyle(height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(
                  text: DocumentQuestionBankParser.templatePrompt,
                ),
              );
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              _showMessage('模板已复制，可粘贴到 Word 或 AI 工具中修改。');
            },
            child: const Text('复制模板'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImport() => _runImport(QuestionFilePicker.pick());

  Future<void> _runImport(Future<PickedQuestionFile?> source) async {
    setState(() => _isImporting = true);
    try {
      final file = await source;
      if (file == null) {
        return;
      }

      final extension = file.name.split('.').last.toLowerCase();
      final preview = extension == 'json'
          ? QuestionBankCodec.decode(file.content)
          : DocumentQuestionBankParser.decode(file.content, file.name);
      if (!mounted) {
        return;
      }
      final decision = await _showImportPreview(preview);
      if (decision == null || !mounted) {
        return;
      }

      await widget.questionBankController.importModules(
        decision.modules,
        strategy: decision.strategy,
      );
      if (!mounted) {
        return;
      }
      _showMessage(
        '已导入 ${preview.modules.length} 个模块、${preview.questionCount} 道题。',
      );
    } on QuestionBankImportException catch (error) {
      if (mounted) {
        _showValidationErrors(error.errors);
      }
    } on FormatException catch (error) {
      if (mounted) {
        _showMessage(error.message.toString());
      }
    } catch (_) {
      if (mounted) {
        _showMessage('导入失败，请检查文件后重试。');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _confirmDeleteModule(QuizModule module) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除模块'),
        content: Text('确定删除“${module.name}”吗？该模块的学习进度也会一起删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removed =
        await widget.questionBankController.deleteImportedModule(module.id);
    if (removed == null) return;
    await widget.progressController.clearForModule(removed);
    if (mounted) _showMessage('已删除模块“${removed.name}”。');
  }

  Future<_ImportDecision?> _showImportPreview(
    QuestionBankImportPreview preview,
  ) {
    return showDialog<_ImportDecision>(
      context: context,
      builder: (_) => _ImportPreviewDialog(
        preview: preview,
        questionBankController: widget.questionBankController,
      ),
    );
  }

  void _showValidationErrors(List<String> errors) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('题库格式有误'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              errors.map((error) => '• $error').join('\n'),
              style: const TextStyle(height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showDocumentTemplate();
            },
            child: const Text('查看模板'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ImportDecision {
  final List<QuizModule> modules;
  final QuestionBankConflictStrategy strategy;

  const _ImportDecision(this.modules, this.strategy);
}

class _ImportPreviewDialog extends StatefulWidget {
  final QuestionBankImportPreview preview;
  final QuestionBankController questionBankController;

  const _ImportPreviewDialog({
    required this.preview,
    required this.questionBankController,
  });

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late final List<TextEditingController> _nameControllers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameControllers = widget.preview.modules
        .map((module) => TextEditingController(text: module.name))
        .toList();
  }

  @override
  void dispose() {
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<QuizModule> _renamedModules() {
    return List.generate(widget.preview.modules.length, (index) {
      final source = widget.preview.modules[index];
      return QuizModule(
        id: source.id,
        name: _nameControllers[index].text.trim(),
        description: source.description,
        days: source.days,
      );
    });
  }

  String? _validateNames(List<QuizModule> modules) {
    if (modules.any((module) => module.name.isEmpty)) return '模块名称不能为空。';
    final names = modules.map((module) => module.name).toSet();
    if (names.length != modules.length) return '模块名称不能重复。';
    return null;
  }

  void _submit(QuestionBankConflictStrategy strategy) {
    final modules = _renamedModules();
    final error = _validateNames(modules);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _ImportDecision(modules, strategy));
  }

  @override
  Widget build(BuildContext context) {
    final modules = _renamedModules();
    final conflicts = _validateNames(modules) == null
        ? widget.questionBankController.conflictingModules(modules)
        : const <QuizModule>[];

    return AlertDialog(
      title: const Text('确认导入题库'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${widget.preview.modules.length} 个模块、${widget.preview.dayCount} 组练习、${widget.preview.questionCount} 道题。',
              ),
              const SizedBox(height: 14),
              for (var index = 0; index < _nameControllers.length; index++) ...[
                TextField(
                  controller: _nameControllers[index],
                  decoration: InputDecoration(
                    labelText: _nameControllers.length == 1
                        ? '模块名称'
                        : '模块 ${index + 1} 名称',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                if (index < _nameControllers.length - 1)
                  const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (conflicts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '发现同名或相同文件身份的模块：${conflicts.map((module) => module.name).join('、')}。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (conflicts.isNotEmpty)
          TextButton(
            onPressed: () => _submit(QuestionBankConflictStrategy.keepBoth),
            child: const Text('另存导入'),
          ),
        ElevatedButton(
          onPressed: () => _submit(
            conflicts.isEmpty
                ? QuestionBankConflictStrategy.keepBoth
                : QuestionBankConflictStrategy.replaceImported,
          ),
          child: Text(conflicts.isEmpty ? '确认导入' : '覆盖导入'),
        ),
      ],
    );
  }
}

class _ThemeModeButton extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onSelected;

  const _ThemeModeButton({
    required this.themeMode,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = themeMode == ThemeMode.dark;
    return IconButton(
      tooltip: isDark ? '切换到白天模式' : '切换到夜间模式',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      ),
      onPressed: () => onSelected(isDark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final QuizModule module;
  final QuizProgressController progressController;
  final VoidCallback? onDelete;

  const _ModuleCard({
    required this.module,
    required this.progressController,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = module.id.hashCode % 3;
    final colors = [AppTheme.blue, AppTheme.purple, AppTheme.orange];
    final color = colors[colorIndex.abs()];
    final totalQuestions = module.days.fold<int>(
      0,
      (total, day) => total + day.questions.length,
    );
    final completed = progressController.completedCount(module.days);
    final completion =
        module.days.isEmpty ? 0.0 : completed / module.days.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ModuleScreen(
                module: module,
                progressController: progressController,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      module.name.isEmpty ? '?' : module.name[0],
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$totalQuestions 题 · $completed/${module.days.length} 组完成',
                          style: TextStyle(
                            fontSize: 12.5,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: '删除模块',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
              if (module.days.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: completion,
                    minHeight: 5,
                    color: completed == module.days.length
                        ? AppTheme.green
                        : color,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyModulesView extends StatelessWidget {
  const _EmptyModulesView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '暂无学习模块',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
