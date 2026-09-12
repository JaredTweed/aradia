import 'dart:convert';
import 'dart:io';
import 'package:aradia/utils/async_keyed_lock.dart';
import 'package:aradia/resources/models/audiobook_file.dart';

/// Names use catalogue order, so adding chapters later preserves their order.
class ChapterDownloads {
  static final _lock = AsyncKeyedLock();
  static String _key(Directory directory) => directory.absolute.path;

  /// Keep catalogue order and remote chapters, substituting only saved audio.
  static Future<List<AudiobookFile>> withDownloadedFiles(
          Directory directory, List<AudiobookFile> catalogue) =>
      _lock.run(_key(directory), () async {
        if (!await directory.exists()) return List<AudiobookFile>.of(catalogue);
        final saved = await _completed(directory);
        final byUrl = {for (final item in saved) item['url']: item};
        final result = <AudiobookFile>[];
        var migrated = false;
        for (var i = 0; i < catalogue.length; i++) {
          final chapter = catalogue[i];
          final downloaded = byUrl[chapter.url] ?? entry(chapter, i);
          final name = downloaded['filename'] as String;
          final file = File('${directory.path}/$name');
          if (!name.contains('/') &&
              !name.contains('\\') &&
              (byUrl.containsKey(chapter.url) || await file.exists())) {
            if (!byUrl.containsKey(chapter.url)) {
              saved.add(downloaded);
              migrated = true;
            }
            result.add(
                AudiobookFile.fromMap({...chapter.toJson(), 'url': file.path}));
          } else {
            result.add(chapter);
          }
        }
        if (migrated) await _write(directory, saved);
        return result;
      });

  static Future<void> delete(Directory directory, String url) =>
      _lock.run(_key(directory), () async {
        final entries = await _completed(directory);
        for (final entry in entries.where((e) => e['url'] == url)) {
          await File('${directory.path}/${entry['filename']}').delete();
        }
        entries.removeWhere((e) => e['url'] == url);
        await _write(directory, entries);
      });

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

  static Future<List<Map<String, dynamic>>> completed(Directory directory) =>
      _lock.run(_key(directory), () => _completed(directory));

  static Future<List<Map<String, dynamic>>> _completed(Directory directory,
      {bool verifyFiles = true}) async {
    final manifest = File('${directory.path}/completed.json');
    if (!await manifest.exists()) return [];
    dynamic decoded;
    try {
      decoded = jsonDecode(await manifest.readAsString());
    } on FormatException {
      return []; // Legacy file discovery can recover the actual audio files.
    }
    if (decoded is! List) return [];
    final result = <Map<String, dynamic>>[];
    for (final value in decoded) {
      if (value is! Map) continue;
      final entry = Map<String, dynamic>.from(value);
      final name = entry['filename'];
      if (name is String &&
          name.isNotEmpty &&
          name != '.' &&
          name != '..' &&
          entry['url'] is String &&
          entry['order'] is int &&
          !name.contains('/') &&
          !name.contains('\\') &&
          (!verifyFiles || await File('${directory.path}/$name').exists())) {
        result.add(entry);
      }
    }
    result.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return result;
  }

  static Future<void> record(Directory directory, Map<String, dynamic> entry) =>
      _lock.run(_key(directory), () async {
        final entries = await _completed(directory, verifyFiles: false);
        entries.removeWhere((e) => e['url'] == entry['url']);
        entries.add(entry);
        await _write(directory, entries);
      });

  static Future<void> _write(
      Directory directory, List<Map<String, dynamic>> entries) async {
    entries.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    await directory.create(recursive: true);
    final temporary = File('${directory.path}/completed.json.tmp');
    await temporary.writeAsString(jsonEncode(entries), flush: true);
    await temporary.rename('${directory.path}/completed.json');
  }
}
