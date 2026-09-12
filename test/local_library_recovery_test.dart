import 'dart:io';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/services/local/local_audiobook_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unavailable storage and one bad record do not erase the cached library',
      () async {
    final directory = await Directory.systemTemp.createTemp('aradia_library');
    Hive.init(directory.path);
    try {
      await LocalAudiobookService.setRootFolderPath('/Audiobooks');
      await LocalAudiobookService.saveAudiobook(LocalAudiobook(
        id: '/Audiobooks/book.mp3',
        title: 'Book',
        author: 'Author',
        folderPath: '/Audiobooks',
        audioFiles: ['/Audiobooks/book.mp3'],
        dateAdded: DateTime(2026),
        lastModified: DateTime(2026),
      ));
      final box = Hive.box('local_audiobooks');
      await box.put('invalid', 'damaged metadata');
      // SAF is unavailable in this test, just as when a folder cannot be read.
      final books = await LocalAudiobookService.refreshAudiobooks();
      expect(books.single.title, 'Book');
      expect(box.containsKey('/Audiobooks/book.mp3'), isTrue);
      expect(
          (await LocalAudiobookService.smartRefreshAudiobooks()).single.title,
          'Book');
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
