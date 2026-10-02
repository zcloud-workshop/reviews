import 'package:flutter/material.dart';

import '../models/quiz.dart';
import '../models/quiz_progress.dart';
import '../services/quiz_progress_controller.dart';
import '../theme/app_theme.dart';
import 'quiz_screen.dart';

class ModuleScreen extends StatelessWidget {
  final QuizModule module;
  final QuizProgressController progressController;

  const ModuleScreen({
    super.key,
    required this.module,
    required this.progressController,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module.name)),
      body: AnimatedBuilder(
        animation: progressController,
        builder: (context, _) {
          if (module.days.isEmpty) {
            return const Center(child: Text('该模块暂无练习组'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: module.days.length,
            itemBuilder: (context, index) {
              final day = module.days[index];
              return _DayCard(
                day: day,
                progressController: progressController,
              );
            },
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final QuizDay day;
  final QuizProgressController progressController;

  const _DayCard({
    required this.day,
    required this.progressController,
  });

  @override
  Widget build(BuildContext context) {
    final progress = progressController.progressFor(day.id);
    final status = progress?.status ?? QuizProgressStatus.notStarted;
    final statusColor = switch (status) {
      QuizProgressStatus.notStarted => AppTheme.blue,
      QuizProgressStatus.inProgress => AppTheme.orange,
      QuizProgressStatus.completed => AppTheme.green,
    };
    final statusLabel = switch (status) {
      QuizProgressStatus.notStarted => '未开始',
      QuizProgressStatus.inProgress => '进行中',
      QuizProgressStatus.completed => progress?.lastAccuracy == null
          ? '已完成'
          : '已完成 ${(progress!.lastAccuracy! * 100).round()}%',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => QuizScreen(
                day: day,
                progressController: progressController,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.questions.length} 道题',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
