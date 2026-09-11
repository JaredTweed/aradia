import 'dart:io';
import 'package:aradia/resources/services/library_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test(
      'retired imports are removed without removing local books or completed downloads',
      () async {
    final directory = await Directory.systemTemp.createTemp('aradia_migration');
    Hive.init(directory.path);
    final favorites = await Hive.openBox('favourite_audiobooks_box');
    final history = await Hive.openBox('history_of_audiobook_box');
    final playing = await Hive.openBox('playing_audiobook_details_box');
    final downloads = await Hive.openBox('download_status_box');
    await favorites.putAll({
      'old': {'origin': 'youtube'},
      'local': {'origin': 'local'}
    });
    await history.putAll({
      'old': {
        'audiobook': {'origin': 'youtube'}
      },
      'saved': {
        'audiobook': {'origin': 'download'}
      }
    });
    await playing.putAll({
      'audiobook': {'origin': 'youtube'},
      'index': 4
    });
    await downloads.putAll({
      'status_done': {'isDownloading': false, 'isCompleted': true},
      'status_busy': {'isDownloading': true}
    });
    await migrateSavedLibrary();
    expect(favorites.keys, ['local']);
    expect(history.keys, ['saved']);
    expect(playing.isEmpty, true);
    expect(downloads.get('status_done')['isCompleted'], true);
    expect(downloads.get('status_busy')['isDownloading'], false);
    await migrateSavedLibrary();
    expect(history.keys, ['saved']);
    await Hive.close();
    await directory.delete(recursive: true);
  });
}
