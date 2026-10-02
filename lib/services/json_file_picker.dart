import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'docx_text_extractor.dart';

class PickedQuestionFile {
  final String name;
  final String content;

  const PickedQuestionFile({required this.name, required this.content});
}

class QuestionFilePicker {
  static const _reader = MethodChannel('com.quiz.reviews/document_reader');
  static const _maxTextBytes = 20 * 1024 * 1024;

  const QuestionFilePicker._();

  static Future<PickedQuestionFile> fromSharedData(
    Map<String, dynamic> data,
  ) async {
    final nativeError = data['error'];
    if (nativeError is String && nativeError.isNotEmpty) {
      throw FormatException(nativeError);
    }
    final rawName = data['name'];
    final mimeType = (data['mimeType'] as String? ?? '').toLowerCase();
    final path = data['path'];
    if (rawName is! String || rawName.isEmpty || path is! String) {
      throw const FormatException('无法读取分享的文件。');
    }

    final extension = _extension(rawName, mimeType);
    return PickedQuestionFile(
      name: _withExtension(rawName, extension),
      content: await _read(path, extension),
    );
  }

  static Future<PickedQuestionFile?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'docx', 'doc'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const FormatException('文件选择器没有返回可读取的文件。');
    }
    final extension = file.extension?.toLowerCase() ?? '';
    return PickedQuestionFile(
      name: file.name,
      content: await _read(path, extension),
    );
  }

  static Future<String> _read(String path, String extension) async {
    switch (extension) {
      case 'docx':
        return DocxTextExtractor.extract(path);
      case 'doc':
        return _extractDoc(path);
      case 'json':
      case 'txt':
        return _readText(path);
      default:
        throw const FormatException('仅支持 .json、.docx 和 .doc 文件。');
    }
  }

  static Future<String> _extractDoc(String path) async {
    try {
      final text =
          await _reader.invokeMethod<String>('extractDoc', {'path': path});
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('DOC 文件没有可读取的文字内容。');
      }
      return text;
    } on PlatformException catch (error) {
      throw FormatException(error.message ?? 'DOC 文件读取失败。');
    }
  }

  static Future<String> _readText(String path) async {
    final file = File(path);
    if (!await file.exists()) throw const FormatException('所选文件不存在。');
    if (await file.length() > _maxTextBytes) {
      throw const FormatException('题库文件不能超过 20 MB。');
    }
    final content = utf8
        .decode(
          await file.readAsBytes(),
          allowMalformed: true,
        )
        .trim();
    if (content.isEmpty) throw const FormatException('文件内容为空。');
    return content;
  }

  static String _extension(String name, String mimeType) {
    final named = name.split('.').last.toLowerCase();
    if (const {'json', 'doc', 'docx', 'txt'}.contains(named)) return named;
    if (mimeType == 'application/json' || mimeType == 'text/json') {
      return 'json';
    }
    if (mimeType == 'application/msword') return 'doc';
    if (mimeType.contains('wordprocessingml.document')) return 'docx';
    if (mimeType == 'text/plain') return 'txt';
    return named;
  }

  static String _withExtension(String name, String extension) {
    final named = name.split('.').last.toLowerCase();
    return const {'json', 'doc', 'docx', 'txt'}.contains(named)
        ? name
        : '$name.$extension';
  }
}

class SharedQuestionFileReceiver {
  static const _channel = MethodChannel('com.quiz.reviews/shared_file');

  const SharedQuestionFileReceiver._();

  static Future<PickedQuestionFile?> initial() async {
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'getInitialSharedFile',
    );
    return data == null ? null : QuestionFilePicker.fromSharedData(data);
  }

  static void listen(
    void Function(PickedQuestionFile file) onFile, {
    void Function(Object error)? onError,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedFile' || call.arguments is! Map) return;
      try {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        onFile(await QuestionFilePicker.fromSharedData(data));
      } catch (error) {
        onError?.call(error);
      }
    });
  }

  static void stop() => _channel.setMethodCallHandler(null);
}
