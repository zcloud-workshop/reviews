enum QuizProgressStatus {
  notStarted,
  inProgress,
  completed,
}

class QuizProgress {
  final String dayId;
  final Map<String, dynamic> answers;
  final bool submitted;
  final double? lastAccuracy;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const QuizProgress({
    required this.dayId,
    required this.answers,
    required this.submitted,
    required this.lastAccuracy,
    required this.updatedAt,
    required this.completedAt,
  });

  QuizProgressStatus get status {
    if (submitted || (answers.isEmpty && lastAccuracy != null)) {
      return QuizProgressStatus.completed;
    }
    if (answers.isNotEmpty) {
      return QuizProgressStatus.inProgress;
    }
    return QuizProgressStatus.notStarted;
  }

  Map<String, dynamic> toJson() {
    return {
      'dayId': dayId,
      'answers': answers,
      'submitted': submitted,
      'lastAccuracy': lastAccuracy,
      'updatedAt': updatedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory QuizProgress.fromJson(Map<String, dynamic> json) {
    final rawAnswers = json['answers'];
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    final completedAt = DateTime.tryParse(
      json['completedAt']?.toString() ?? '',
    );
    final rawAccuracy = json['lastAccuracy'];

    return QuizProgress(
      dayId: json['dayId']?.toString() ?? '',
      answers: rawAnswers is Map
          ? rawAnswers.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, dynamic>{},
      submitted: json['submitted'] == true,
      lastAccuracy: rawAccuracy is num ? rawAccuracy.toDouble() : null,
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: completedAt,
    );
  }
}
