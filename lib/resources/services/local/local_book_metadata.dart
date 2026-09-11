import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:hive/hive.dart';

/// Overrides survive rescans and do not rename or rewrite the user's audio files.
class LocalBookMetadata {
  static Future<void> updateCover(LocalAudiobook book, String? cover) async {
    final key = MediaHelper.bookKeyForLocal(book);
    for (final name in [
      'playing_audiobook_details_box',
      'favourite_audiobooks_box'
    ]) {
      final box = await Hive.openBox(name);
      final entryKey =
          name == 'playing_audiobook_details_box' ? 'audiobook' : key;
      final value = box.get(entryKey);
      if (value is Map && value['id'] == key) {
        await box.put(entryKey,
            Map<String, dynamic>.from(value)..['lowQCoverImage'] = cover ?? '');
      }
    }
    final history = HistoryOfAudiobook();
    if (history.isAudiobookInHistory(key)) {
      final old = history.getHistoryOfAudiobookItem(key);
      await history.addToHistory(
          old.audiobook.copyWith(lowQCoverImage: cover ?? ''),
          old.audiobookFiles
              .map((file) => AudiobookFile.fromMap(
                  {...file.toMap(), 'highQCoverImage': cover ?? ''}))
              .toList(),
          old.index,
          old.position);
    }
  }

  static Future<List<LocalAudiobook>> apply(List<LocalAudiobook> books) async {
    final box = await Hive.openBox('local_book_metadata');
    return books.map((book) {
      final value = box.get(MediaHelper.bookKeyForLocal(book));
      if (value is! Map) return book;
      return book.copyWith(
          title: value['title'] as String?, author: value['author'] as String?);
    }).toList();
  }

  static Future<LocalAudiobook> save(
      LocalAudiobook book, String title, String author) async {
    title = title.trim();
    author = author.trim();
    if (title.isEmpty) throw ArgumentError('Please enter a title.');
    if (author.isEmpty) author = 'Unknown author';
    final key = MediaHelper.bookKeyForLocal(book);
    final fields = {'title': title, 'author': author};
    await (await Hive.openBox('local_book_metadata')).put(key, fields);
    final updated = book.copyWith(title: title, author: author);
    await (await Hive.openBox('local_audiobooks'))
        .put(book.id, updated.toMap());
    final playing = await Hive.openBox('playing_audiobook_details_box');
    final current = playing.get('audiobook');
    if (current is Map && current['id'] == key) {
      await playing.put(
          'audiobook', Map<String, dynamic>.from(current)..addAll(fields));
    }
    final favorites = await Hive.openBox('favourite_audiobooks_box');
    final favorite = favorites.get(key);
    if (favorite is Map) {
      await favorites.put(
          key, Map<String, dynamic>.from(favorite)..addAll(fields));
    }
    final history = HistoryOfAudiobook();
    if (history.isAudiobookInHistory(key)) {
      final old = history.getHistoryOfAudiobookItem(key);
      await history.addToHistory(
          old.audiobook.copyWith(title: title, author: author),
          old.audiobookFiles,
          old.index,
          old.position);
    }
    return updated;
  }
}
