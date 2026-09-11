import 'dart:convert';
import 'dart:io';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:hive/hive.dart';
import 'package:saf/saf.dart';
import 'chapter_parser.dart';
import 'cover_image_service.dart';
import 'local_audiobook_service.dart';

class LocalBookLibrary {
  static Future<Audiobook> audiobook(LocalAudiobook book) async =>
      Audiobook.fromMap({
        'id': MediaHelper.bookKeyForLocal(book),
        'title': book.title,
        'author': book.author,
        'description': book.description ?? '',
        'lowQCoverImage': await resolveCoverForLocal(book),
        'subject': book.genre == null ? [] : [book.genre],
        'origin': 'local',
      });

  static Future<List<AudiobookFile>> filesForId(String id,
      {List<AudiobookFile>? fallback}) async {
    final books = await LocalAudiobookService.getAllAudiobooks();
    for (final book in books) {
      if (MediaHelper.bookKeyForLocal(book) == id || book.id == id) {
        return chapters(book);
      }
    }
    if (fallback != null && fallback.isNotEmpty) return fallback;
    throw StateError(
        'This local book is unavailable. Check your audiobook folder in Settings.');
  }

  static final _pending = <String, Future<List<AudiobookFile>>>{};
  static Future<List<AudiobookFile>> chapters(LocalAudiobook book) {
    final key = MediaHelper.bookKeyForLocal(book);
    return _pending.putIfAbsent(
        key,
        () => _chapters(book).whenComplete(() {
              _pending.remove(key);
            }));
  }

  static Future<List<AudiobookFile>> _chapters(LocalAudiobook book) async {
    final key = MediaHelper.bookKeyForLocal(book);
    final cover = await resolveCoverForLocal(book);
    final cache = await Hive.openBox('local_chapters_box');
    final signature = jsonEncode(
        [3, book.audioFiles, book.lastModified.millisecondsSinceEpoch]);
    final saved = cache.get(key);
    if (saved is Map && saved['signature'] == signature) {
      return (saved['files'] as List)
          .map((m) => AudiobookFile.fromMap(
              {...Map<String, dynamic>.from(m), 'highQCoverImage': cover}))
          .toList();
    }
    final root = await LocalAudiobookService.getRootFolderPath();
    final result = <AudiobookFile>[];
    for (var index = 0; index < book.audioFiles.length; index++) {
      final path = MediaHelper.decodePath(book.audioFiles[index]);
      final metadata =
          await MediaHelper.getAudioMetadata(path, root ?? book.folderPath);
      final totalMs = metadata.trackDuration ??
          (book.audioFiles.length == 1
              ? book.totalDuration?.inMilliseconds
              : null);
      if (book.audioFiles.length == 1) {
        File? readable;
        try {
          final file = File(path);
          final handle = await file.open();
          await handle.close();
          readable = file;
        } catch (_) {
          if (root != null) {
            final cached = await Saf(root)
                .singleCache(filePath: path, directory: root)
                .timeout(const Duration(seconds: 30));
            if (cached != null) readable = File(cached);
          }
        }
        if (readable != null) {
          final cues = await ChapterParser.parseFile(readable);
          if (cues.length > 1) {
            for (var i = 0; i < cues.length; i++) {
              final start = cues[i].startMs;
              final end = i + 1 < cues.length ? cues[i + 1].startMs : totalMs;
              result.add(AudiobookFile.chapterSlice(
                  identifier: key,
                  url: MediaHelper.makeSafUriFromPath(path),
                  parentTitle: book.title,
                  track: i + 1,
                  chapterTitle: cues[i].title,
                  startMs: start,
                  durationMs: end != null && end > start ? end - start : null,
                  highQCoverImage: cover));
            }
            break;
          }
        }
      }
      final filename = path.split('/').last;
      result.add(AudiobookFile.fromMap({
        'identifier': key,
        'track': index + 1,
        'title': metadata.trackName?.isNotEmpty == true
            ? metadata.trackName
            : filename.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        'name': filename,
        'url': MediaHelper.makeSafUriFromPath(path),
        'length': totalMs == null ? null : totalMs / 1000,
        'highQCoverImage': cover,
      }));
    }
    // Retry unknown durations on a future open instead of caching failed metadata forever.
    if (result.isNotEmpty && result.every((file) => file.duration != null)) {
      await cache.put(key, {
        'signature': signature,
        'files': result.map((f) => f.toMap()).toList()
      });
    }
    return result;
  }
}
