import 'dart:io';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/services/local/local_book_metadata.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test(
      'local edits survive fresh scans and update active and favorite metadata',
      () async {
    final directory = await Directory.systemTemp.createTemp('aradia_metadata');
    Hive.init(directory.path);
    try {
      final book = LocalAudiobook(
          title: 'File name',
          author: 'Unknown',
          folderPath: '/books',
          audioFiles: ['/books/book.m4b'],
          dateAdded: DateTime(2026),
          lastModified: DateTime(2026),
          id: 'scan-id');
      final key = MediaHelper.bookKeyForLocal(book);
      final playing = await Hive.openBox('playing_audiobook_details_box');
      final favorites = await Hive.openBox('favourite_audiobooks_box');
      await playing.put('audiobook', {'id': key, 'title': book.title});
      await favorites.put(key, {'id': key, 'title': book.title});
      final edited =
          await LocalBookMetadata.save(book, ' A real title ', ' An author ');
      expect(edited.title, 'A real title');
      expect(
          (await LocalBookMetadata.apply([book])).single.author, 'An author');
      expect(playing.get('audiobook')['title'], 'A real title');
      expect(favorites.get(key)['author'], 'An author');
      expect(edited.audioFiles, book.audioFiles);
      await expectLater(
          LocalBookMetadata.save(book, ' ', ''), throwsArgumentError);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
