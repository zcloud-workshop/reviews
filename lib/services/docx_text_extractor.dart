import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class DocxTextExtractor {
  static const _maxFileBytes = 20 * 1024 * 1024;
  static const _maxXmlBytes = 30 * 1024 * 1024;

  const DocxTextExtractor._();

  static Future<String> extract(String path) async {
    try {
      return await Isolate.run(() => _extract(path));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('DOCX 文件已损坏或无法读取。');
    }
  }

  static String _extract(String path) {
    final file = File(path);
    if (!file.existsSync()) throw const FormatException('所选文件不存在。');
    if (file.lengthSync() > _maxFileBytes) {
      throw const FormatException('DOCX 文件不能超过 20 MB。');
    }

    final archive = ZipDecoder().decodeBytes(
      file.readAsBytesSync(),
      verify: true,
    );
    final documentFile = archive.findFile('word/document.xml');
    if (documentFile == null || documentFile.size > _maxXmlBytes) {
      throw const FormatException('文件不是有效的 DOCX 文档。');
    }

    final xml = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>),
    );
    final lines = xml.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'p')
        .map(_paragraphText)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) throw const FormatException('DOCX 文件没有可读取的文字。');
    return lines.join('\n');
  }

  static String _paragraphText(XmlElement paragraph) {
    final buffer = StringBuffer();
    for (final node in paragraph.descendants.whereType<XmlElement>()) {
      switch (node.name.local) {
        case 't':
          buffer.write(node.innerText);
        case 'tab':
          buffer.write('\t');
        case 'br':
        case 'cr':
          buffer.write('\n');
      }
    }
    return buffer.toString();
  }
}
