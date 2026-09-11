import 'dart:convert';
import 'dart:io';
import 'package:aradia/resources/models/audiobook_file.dart';

/// Names use catalogue order, so adding chapters later preserves their order.
class ChapterDownloads {
  static Future<void> delete(Directory directory, String url) async {
    final entries = await completed(directory);
    for (final entry in entries.where((e) => e['url'] == url)) {
      await File('${directory.path}/${entry['filename']}').delete();
    }
    entries.removeWhere((e) => e['url'] == url);
    final temporary = File('${directory.path}/completed.json.tmp');
    await temporary.writeAsString(jsonEncode(entries), flush: true);
    await temporary.rename('${directory.path}/completed.json');
  }

  static Map<String, dynamic> entry(AudiobookFile chapter, int index) {
    final title = (chapter.title ?? 'Chapter ${index + 1}')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final short = title.length > 100 ? title.substring(0, 100) : title;
    return {
      ...chapter.toJson(),
      'order': index,
      'filename': '${(index + 1).toString().padLeft(5, '0')}-$short.mp3'
    };
  }

  static Future<List<Map<String, dynamic>>> completed(
      Directory directory) async {
    final manifest = File('${directory.path}/completed.json');
    if (!await manifest.exists()) return [];
    final entries = (jsonDecode(await manifest.readAsString()) as List)
        .map((e) => Map<String, dynamic>.from(e as Map));
    final result = <Map<String, dynamic>>[];
    for (final entry in entries) {
      final name = entry['filename'] as String;
      if (!name.contains('/') &&
          !name.contains('\\') &&
          await File('${directory.path}/$name').exists()) {
        result.add(entry);
      }
    }
    result.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return result;
  }

  static Future<void> record(
      Directory directory, Map<String, dynamic> entry) async {
    final entries = await completed(directory);
    entries.removeWhere((e) => e['url'] == entry['url']);
    entries.add(entry);
    entries.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    final temporary = File('${directory.path}/completed.json.tmp');
    await temporary.writeAsString(jsonEncode(entries), flush: true);
    await temporary.rename('${directory.path}/completed.json');
  }
}
