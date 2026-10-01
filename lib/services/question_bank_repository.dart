import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/quiz.dart';
import 'question_bank_codec.dart';

class QuestionBankRepository {
  static const _storageKey = 'imported_question_banks_v1';

  SharedPreferences? _preferences;

  QuestionBankRepository({SharedPreferences? preferences})
      : _preferences = preferences;

  Future<List<QuizModule>> loadImportedModules() async {
    final encoded = (await _getPreferences()).getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return const <QuizModule>[];
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map || decoded['modules'] is! List) {
        return const <QuizModule>[];
      }
      final source = jsonEncode({
        'formatVersion': QuestionBankCodec.formatVersion,
        'modules': decoded['modules'],
      });
      return QuestionBankCodec.decode(source).modules;
    } catch (_) {
      return const <QuizModule>[];
    }
  }

  Future<void> saveImportedModules(List<QuizModule> modules) async {
    final preferences = await _getPreferences();
    if (modules.isEmpty) {
      await preferences.remove(_storageKey);
      return;
    }
    final encoded = jsonEncode({
      'formatVersion': QuestionBankCodec.formatVersion,
      'modules': modules.map(_moduleToJson).toList(growable: false),
    });
    await preferences.setString(_storageKey, encoded);
  }

  Future<SharedPreferences> _getPreferences() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Map<String, dynamic> _moduleToJson(QuizModule module) {
    return {
      'id': module.id,
      'name': module.name,
      'description': module.description,
      'days': module.days
          .map(
            (day) => {
              'id': day.id,
              'title': day.title,
              'questions': day.questions
                  .map(
                    (question) => {
                      'id': question.id,
                      'type': question.type.name,
                      'content': question.content,
                      if (question.options.isNotEmpty)
                        'options': question.options,
                      'answer': question.answer,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }
}
